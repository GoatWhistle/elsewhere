module Foresight
  module Relevance
    RELEVANT_WEIGHT = Planning::Taxonomy::WEIGHT_SCALE.begin +
                      (Planning::Taxonomy::WEIGHT_SCALE.end - Planning::Taxonomy::WEIGHT_SCALE.begin) / 2.0

    module_function

    def dna_for(future)
      version_id = future["travel_dna_version_id"]
      return nil unless version_id

      Planning::TravelDna.find(version_id: version_id)
    rescue StandardError
      nil
    end

    def elements(dna) = Array(dna && dna["elements"])

    def element_for(dna, dimension)
      elements(dna).find { |element| element["dimension"] == dimension }
    end

    def relevant?(dna, dimension)
      return true if dna.nil?

      element = element_for(dna, dimension)
      return false unless element
      return true if %w[aversion hard_constraint].include?(element["kind"])

      element["weight"].to_f >= RELEVANT_WEIGHT
    end

    def filter(findings, dna)
      findings.select { |finding| relevant?(dna, finding.affected_dimension) }
    end

    def climate_target(dna)
      element = element_for(dna, "climate_warm")
      return "warm" unless element

      element["target"].to_s.empty? ? "warm" : element["target"].to_s
    end
  end
end
