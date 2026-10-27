module Supply
  module RateValidation
    BIAS_TOLERANCE = 0.05

    MIN_SEASONAL_SPREAD = 1.4

    Check = Struct.new(:name, :passed, :detail, keyword_init: true)

    module_function

    def report(calibrations: nil, price_levels: nil)
      calibrations ||= from_database
      price_levels ||= levels_from_database
      by_city = calibrations.group_by { |row| row["city_code"] }

      checks = [
        anchored(by_city),
        unbiased(by_city),
        seasonal_spread(by_city),
        rank_preserving(by_city, price_levels)
      ]

      { "model_version" => RateModel::VERSION, "destinations" => by_city.keys.sort,
        "checks" => checks.map { |check| check.to_h.transform_keys(&:to_s) },
        "passed" => checks.all?(&:passed) }
    end

    def anchored(by_city)
      factors = by_city.values.flatten.map { |row| row["seasonal_factor"].to_f }
      outside = factors.reject { |factor| factor.between?(RateModel::FACTOR_MIN, RateModel::FACTOR_MAX) }

      Check.new(name: "anchored to the observed base", passed: outside.empty?,
                detail: "#{factors.length} factors in #{factors.min}–#{factors.max}, " \
                        "bounds #{RateModel::FACTOR_MIN}–#{RateModel::FACTOR_MAX}")
    end

    def unbiased(by_city)
      means = by_city.transform_values do |rows|
        factors = rows.map { |row| row["seasonal_factor"].to_f }
        (factors.sum / factors.length).round(4)
      end
      worst = means.max_by { |_city, mean| (mean - 1).abs }

      Check.new(name: "unbiased over a year", passed: (worst.last - 1).abs <= BIAS_TOLERANCE,
                detail: means.map { |city, mean| "#{city} #{mean}" }.join(" · ") +
                        " (tolerance ±#{BIAS_TOLERANCE})")
    end

    def seasonal_spread(by_city)
      spreads = by_city.transform_values do |rows|
        factors = rows.map { |row| row["seasonal_factor"].to_f }
        (factors.max / factors.min).round(2)
      end
      thin = spreads.select { |_city, spread| spread < MIN_SEASONAL_SPREAD }

      Check.new(name: "a season worth shifting", passed: thin.empty?,
                detail: spreads.map { |city, spread| "#{city} ×#{spread}" }.join(" · ") +
                        " (minimum ×#{MIN_SEASONAL_SPREAD})")
    end

    def rank_preserving(by_city, price_levels)
      broken = by_city.keys.sort.reject do |city|
        bases = Array(price_levels[city]).sort
        next true if bases.length < 2

        by_city[city].all? do |row|
          rated = bases.map { |base| (base * row["seasonal_factor"].to_f).round }
          rated == rated.sort
        end
      end

      Check.new(name: "order of the corpus preserved", passed: broken.empty?,
                detail: broken.empty? ? "every destination keeps its price order in all 12 months" : broken.join(", "))
    end

    def from_database
      PriceCalibrationRecord.where(model_version: RateModel::VERSION)
                            .pluck(:city_code, :month, :seasonal_factor)
                            .map { |city, month, factor| { "city_code" => city, "month" => month, "seasonal_factor" => factor.to_f } }
    end

    def levels_from_database
      PropertyRecord.where.not(price_level_minor: nil).pluck(:city_code, :price_level_minor)
                    .group_by(&:first).transform_values { |rows| rows.map(&:last) }
    end
  end
end
