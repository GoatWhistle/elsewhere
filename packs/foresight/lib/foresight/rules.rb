module Foresight
  module Rules
    Finding = Struct.new(:risk_type, :affected_dimension, :claim_kind, :statement, :evidence,
                         :measurement, :threshold, :unit, :direction, :completeness, :inputs,
                         keyword_init: true) do
      def exceedance
        return nil if measurement.nil? || threshold.nil? || threshold.zero?

        direction == :below ? (threshold - measurement) / threshold.to_f : (measurement - threshold) / threshold.to_f
      end

      def triggered? = exceedance.to_f.positive?
    end

    ALL = [Rules::NightNoise, Rules::Walkability, Rules::WeatherMismatch, Rules::TransferDifficulty].freeze

    module_function

    def findings(evidence, dna: nil)
      ALL.filter_map do |rule|
        next unless evidence.available?(rule::RISK_TYPE)

        if rule == WeatherMismatch
          rule.call(evidence, target: Relevance.climate_target(dna))
        else
          rule.call(evidence)
        end
      end
    end
  end
end
