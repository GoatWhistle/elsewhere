module Foresight
  module Rules
    module Walkability
      RISK_TYPE = "walkability".freeze
      DIMENSION = "walkability".freeze

      DENSITY_THRESHOLD = 0.35

      RESTAURANTS_THRESHOLD = 5

      module_function

      def call(evidence)
        density = evidence.geo_value("poi_density").to_f
        restaurants = evidence.geo_value("restaurant_count_500m").to_i
        walk_metres = evidence.geo_value("walk_network_m_500m")

        parts = ["в радиусе 500 м плотность точек притяжения #{density.round(2)} (порог #{DENSITY_THRESHOLD})",
                 "ресторанов и кафе: #{restaurants}"]
        parts << "пешеходной сети: #{walk_metres} м" if walk_metres

        Finding.new(
          risk_type: RISK_TYPE, affected_dimension: DIMENSION, claim_kind: "derived_metric",
          measurement: density, threshold: DENSITY_THRESHOLD, unit: "density", direction: :below,
          completeness: walk_metres ? 1.0 : 2.0 / 3,
          statement: "Пешком отсюда доступно мало: #{parts.join(", ")}. " \
                     "Это расчёт по количеству объектов вокруг, а не оценка того, приятно ли идти.",
          evidence: [{ "source" => "geo",
                       "excerpt" => parts.join("; ") + ".",
                       "observed_at" => evidence.geo["computed_at"] || Date.today.iso8601,
                       "count" => restaurants }],
          inputs: { "poi_density" => density.round(3), "restaurant_count_500m" => restaurants,
                    "walk_network_m_500m" => walk_metres }
        )
      end
    end
  end
end
