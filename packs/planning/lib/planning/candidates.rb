require_relative "constraints"
require_relative "match"

module Planning
  module Candidates
    DESTINATION_LIMIT = 8      # stage 2, K ≈ 8
    PROPERTIES_PER_DESTINATION = 3
    PROPERTY_POOL = 30         # how many of a destination's properties to weigh up

    GEOGRAPHIES = %w[city mountains sea].freeze

    Candidate = Struct.new(:destination, :property, :match, :geography, keyword_init: true)

    module_function

    def destinations(constraints, dna, months:)
      survivors = Constraints.destinations(Supply::Catalog.destinations, constraints).survivors
      return [] if survivors.empty?

      ranked = survivors.map { |destination| [destination, pre_score(destination, dna, months)] }
                        .sort_by { |_destination, score| -score }

      with_quota(ranked).first(DESTINATION_LIMIT)
    end

    def pre_score(destination, dna, months)
      element = Array(dna["elements"]).find { |item| item["dimension"] == "climate_warm" }
      return 0.5 unless element

      temperatures = Array(months).filter_map do |month|
        (Supply::Climate.normals(city_code: destination.city_code, month: month) || {})["temp_mean_c"]
      end
      return 0.5 if temperatures.empty?

      Curves.climate(temperatures.sum.to_f / temperatures.length) || 0.5
    end

    def with_quota(ranked)
      by_type = GEOGRAPHIES.to_h do |type|
        codes = Supply::Catalog.destinations(axes: { geography: type }).map(&:city_code)
        [type, ranked.find { |destination, _score| codes.include?(destination.city_code) }]
      end.compact

      promoted = by_type.values.compact
      promoted + (ranked - promoted)
    end

    def properties(destinations, dna, months:)
      destinations.flat_map do |destination, _score|
        pool = Supply::Catalog.properties(city_code: destination.city_code, limit: PROPERTY_POOL)

        pool.map { |property| build(destination, property, dna, months) }
            .sort_by { |candidate| Match.ranking_key(candidate.match) }
            .first(PROPERTIES_PER_DESTINATION)
      end
    end

    def build(destination, property, dna, months)
      features = Match.features_for(property: property, city_code: destination.city_code, months: months)
      Candidate.new(destination: destination, property: property, match: Match.score(dna: dna, features: features),
                    geography: geography_of(destination))
    end

    def geography_of(destination)
      GEOGRAPHIES.find do |type|
        Supply::Catalog.destinations(axes: { geography: type }).any? { |item| item.city_code == destination.city_code }
      end
    end

    def shortlist(dna, constraints, months:)
      properties(destinations(constraints, dna, months: months), dna, months: months)
    end
  end
end
