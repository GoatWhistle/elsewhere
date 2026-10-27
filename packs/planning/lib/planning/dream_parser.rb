require_relative "taxonomy"
require_relative "lexicon"

module Planning
  module DreamParser
    LADDER = [Taxonomy::WEIGHT_SCALE.end, 0.9, 0.8, 0.7, 0.6, 0.55, 0.5, 0.45, 0.4].freeze
    LADDER_FLOOR = 0.35

    NAMED = 1.0            # the user said it, in their own words
    DERIVED = 0.6          # we inferred it from something else they said
    TAXONOMY_DEFAULT = 0.3 # nobody said anything; this is just the vocabulary's default

    INFERENCES = {
      "car_free" => %w[walkability transfer_simplicity],
      "sea_access" => %w[climate_warm],
      "walkability" => %w[car_free]
    }.freeze

    TOLERANCE = { "nature_vs_city" => 0.15, "nightlife" => 0.2, "crowds" => 0.2, "climate_warm" => 3.0 }.freeze

    SCHEMA = {
      "type" => "object",
      "additionalProperties" => false,
      "properties" => {
        "dimensions" => {
          "type" => "array",
          "items" => {
            "type" => "object", "additionalProperties" => false,
            "properties" => { "dimension" => { "type" => "string", "enum" => Taxonomy.all },
                              "target" => {}, "quote" => { "type" => "string" } },
            "required" => %w[dimension quote]
          }
        },
        "ranking" => { "type" => "array", "items" => { "type" => "string" } },
        "unmatched" => { "type" => "array", "items" => { "type" => "string" } }
      },
      "required" => %w[dimensions ranking unmatched]
    }.freeze

    Result = Struct.new(:elements, :unmatched_intent, :clarifications, :party, :degraded, :degraded_reason,
                        keyword_init: true)

    module_function

    def parse(dream_text, response: nil)
      outcome = AI::Task.run(task: "parse_dream", input: { "dream" => dream_text.to_s }, schema: SCHEMA,
                             fallback: ->(input) { fallback(input["dream"]) }, response: response)
      answer = outcome.value || fallback(dream_text)

      stated = stated_elements(answer)
      inferred = inferred_elements(stated)
      ordered = rank(stated, inferred, answer["ranking"] ) + defaults(stated + inferred)
      ordered = rank(ordered.uniq { |element| element["dimension"] }, [], answer["ranking"])

      Result.new(
        elements: ordered, unmatched_intent: Array(answer["unmatched"]).uniq,
        clarifications: Clarifications.for(ordered, dream_text),
        party: Lexicon.party(dream_text),
        degraded: outcome.degraded?, degraded_reason: outcome.reason
      )
    end

    def fallback(dream_text)
      matches = Lexicon.matches(dream_text)
      {
        "dimensions" => matches.map { |m| { "dimension" => m.dimension, "target" => m.target, "quote" => m.quote } },
        "ranking" => matches.map(&:dimension),
        "unmatched" => Lexicon.leftovers(dream_text, matches)
      }
    end

    def stated_elements(answer)
      Array(answer["dimensions"]).filter_map do |raw|
        dimension = raw["dimension"]
        next unless Taxonomy.known?(dimension)

        element(dimension, raw["target"], "stated", NAMED)
      end.uniq { |element| element["dimension"] }
    end

    def inferred_elements(stated)
      named = stated.map { |element| element["dimension"] }

      INFERENCES.flat_map do |source, targets|
        next [] unless named.include?(source)

        targets.reject { |target| named.include?(target) }
               .map { |target| element(target, default_target(target), "inferred", DERIVED, derived_from: source) }
      end.uniq { |element| element["dimension"] }
    end

    def rank(stated, inferred, ranking)
      order = Array(ranking)
      sorted = stated.sort_by { |element| order.index(element["dimension"]) || order.length }
      scored = (sorted + inferred).reject { |element| Taxonomy.hard?(element["dimension"]) }

      scored.each_with_index { |element, index| element["weight"] = LADDER[index] || LADDER_FLOOR }
      (sorted + inferred).map { |element| element.merge("weight" => Taxonomy.hard?(element["dimension"]) ? nil : element["weight"]) }
    end

    DEFAULTS = %w[comfort food_quality walkability].freeze

    def defaults(elements)
      return [] if elements.any? { |element| Taxonomy.measurable?(element["dimension"]) }

      DEFAULTS.map { |dimension| element(dimension, nil, "default", TAXONOMY_DEFAULT) }
    end

    def element(dimension, target, provenance, confidence, derived_from: nil)
      {
        "dimension" => dimension,
        "kind" => Taxonomy.kind(dimension),
        "target" => target.nil? ? default_target(dimension) : target,
        "weight" => nil,
        "tolerance" => TOLERANCE[dimension],
        "provenance" => provenance,
        "confidence" => confidence
      }.tap { |built| built["_derived_from"] = derived_from if derived_from }
    end

    def default_target(dimension)
      case Taxonomy.family(dimension)
      when :more_is_better then "high"
      when :target then dimension == "climate_warm" ? 25.0 : 0.5
      end
    end
  end
end
