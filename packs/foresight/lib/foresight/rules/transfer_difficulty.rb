module Foresight
  module Rules
    module TransferDifficulty
      RISK_TYPE = "transfer_difficulty".freeze
      DIMENSION = "transfer_simplicity".freeze

      THRESHOLD_M = 40_000
      THRESHOLD_MIN = 60

      module_function

      def call(evidence)
        metres = evidence.geo_value("airport_distance_m").to_f
        minutes = evidence.geo_value("airport_transfer_min")
        airport = evidence.geo_value("airport_name")

        if minutes
          measurement, threshold, unit = minutes.to_f, THRESHOLD_MIN.to_f, "min"
          excerpt = "Трансфер из аэропорта#{airport ? " (#{airport})" : ""}: #{minutes} мин по дорогам, " \
                    "#{(metres / 1000).round(1)} км по прямой."
        else
          measurement, threshold, unit = metres, THRESHOLD_M.to_f, "m"
          excerpt = "Аэропорт#{airport ? " (#{airport})" : ""} в #{(metres / 1000).round(1)} км по прямой; " \
                    "времени в пути нет — дорога всегда длиннее прямой, так что это нижняя оценка."
        end

        Finding.new(
          risk_type: RISK_TYPE, affected_dimension: DIMENSION, claim_kind: "derived_metric",
          measurement: measurement, threshold: threshold, unit: unit, direction: :above,
          completeness: minutes ? 1.0 : 0.5,
          statement: "Дорога от аэропорта заметная: #{excerpt}",
          evidence: [{ "source" => "geo", "excerpt" => excerpt,
                       "observed_at" => evidence.geo["computed_at"] || Date.today.iso8601, "count" => nil }],
          inputs: { "airport_distance_m" => metres.round, "airport_transfer_min" => minutes,
                    "airport_name" => airport }
        )
      end
    end
  end
end
