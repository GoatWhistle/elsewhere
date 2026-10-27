require "date"

module Foresight
  module Evidence
    REQUIREMENTS = {
      "night_noise" => { geo: %w[nearest_major_road_m road_class] },
      "walkability" => { geo: %w[poi_density restaurant_count_500m] },
      "weather_mismatch" => { climate: %w[temp_mean_c] },
      "transfer_difficulty" => { geo: %w[airport_distance_m] },
      "crowds" => { reviews: %w[documents] },
      "construction" => { reviews: %w[documents] },
      "weak_transport" => { reviews: %w[documents] },
      "room_location_mismatch" => { reviews: %w[documents] },
      "seasonal_closure" => { reviews: %w[documents] }
    }.freeze

    Bundle = Struct.new(:property_id, :city_code, :check_in, :check_out, :months,
                        :geo, :climate, :reviews, :sources, keyword_init: true) do
      def geo_value(name) = geo[name]

      def climate_value(name, month)
        (climate[month] || {})[name]
      end

      def available?(risk_type)
        REQUIREMENTS.fetch(risk_type, {}).all? do |source, fields|
          case source
          when :geo then fields.all? { |field| !geo_value(field).nil? }
          when :climate then months.any? && fields.all? { |field| months.all? { |m| !climate_value(field, m).nil? } }
          when :reviews then reviews.available
          end
        end
      end

      def unavailable_reason(risk_type)
        REQUIREMENTS.fetch(risk_type, {}).filter_map do |source, fields|
          case source
          when :geo
            missing = fields.reject { |field| geo_value(field) }
            next if missing.empty?

            "no #{missing.join(", ")} for this property" + (geo.dig("unassessed", missing.first) ? " (#{geo["unassessed"][missing.first]})" : "")
          when :climate
            next if months.any? && fields.all? { |field| months.all? { |m| climate_value(field, m) } }

            "no climate normals for #{city_code}"
          when :reviews
            next if reviews.available

            reviews.reason
          end
        end.join("; ")
      end
    end

    module_function

    def for_future(future)
      property_id = future.dig("accommodation", "catalogue_id")
      city_code = future.dig("destination", "city_code")
      check_in = Date.parse(future["check_in"].to_s)
      check_out = Date.parse(future["check_out"].to_s)
      months = (check_in...check_out).map(&:month).uniq

      geo = Supply::Geo.features(property_id: property_id) || {}
      climate = months.to_h { |month| [month, Supply::Climate.normals(city_code: city_code, month: month) || {}] }
      reviews = Supply::Reviews.for_property(property_id: property_id)

      Bundle.new(
        property_id: property_id, city_code: city_code, check_in: check_in, check_out: check_out,
        months: months, geo: geo, climate: climate, reviews: reviews,
        sources: {
          "geo" => { "freshness" => geo["freshness"], "available" => !geo.empty? },
          "weather" => { "freshness" => climate.values.first&.dig("freshness"), "available" => climate.values.any? { |n| n["temp_mean_c"] } },
          "review" => { "available" => reviews.available, "reason" => reviews.reason, "freshness" => reviews.freshness }
        }
      )
    end
  end
end
