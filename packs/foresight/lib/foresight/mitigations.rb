require_relative "rules"
require_relative "scoring"

module Foresight
  module Mitigations
    CANDIDATE_LIMIT = 60

    ALTERNATIVE_FEATURE = {
      "night_noise" => { field: "nearest_major_road_m", better: :higher },
      "walkability" => { field: "poi_density", better: :higher },
      "transfer_difficulty" => { field: "airport_distance_m", better: :lower }
    }.freeze

    MONTH_WINDOW = 3

    module_function

    def for_finding(finding, evidence, future)
      case finding.risk_type
      when "weather_mismatch" then [shift_dates(finding, evidence, future)].compact
      else [swap_property(finding, evidence, future)].compact
      end
    end

    def swap_property(finding, evidence, future)
      spec = ALTERNATIVE_FEATURE[finding.risk_type]
      return nil unless spec

      candidate = best_alternative(evidence, spec, finding)
      return nil unless candidate

      alternative, features = candidate
      after = severity_with(finding, features[spec[:field]].to_f)
      return nil unless better?(after, Scoring.severity(finding))

      price = price_difference(future, evidence, alternative)
      return nil unless price

      {
        "id" => mitigation_id(future, finding, "alternative_property"),
        "description" => description_for(finding, alternative, features, spec),
        "price_change" => price,
        "severity_after" => after
      }
    end

    def best_alternative(evidence, spec, _finding)
      Supply::Catalog.properties(city_code: evidence.city_code, limit: CANDIDATE_LIMIT)
                     .reject { |property| property.catalogue_id == evidence.property_id }
                     .filter_map do |property|
        features = Supply::Geo.features(property_id: property.catalogue_id) || {}
        value = features[spec[:field]]
        next if value.nil?

        [property, features]
      end.min_by do |_property, features|
        value = features[spec[:field]].to_f
        spec[:better] == :higher ? -value : value
      end
    end

    def severity_with(finding, measurement)
      Scoring.severity(Rules::Finding.new(
                         risk_type: finding.risk_type, affected_dimension: finding.affected_dimension,
                         claim_kind: finding.claim_kind, statement: finding.statement, evidence: finding.evidence,
                         measurement: measurement, threshold: finding.threshold, direction: finding.direction,
                         completeness: finding.completeness
                       ))
    end

    ORDER = %w[low medium high].freeze
    def better?(after, before) = ORDER.index(after) < ORDER.index(before)

    def description_for(finding, property, features, spec)
      value = features[spec[:field]]
      readable =
        case finding.risk_type
        when "night_noise" then "ближайшая крупная дорога в #{value.to_i} м вместо #{finding.measurement.round} м"
        when "walkability" then "плотность вокруг #{value.to_f.round(2)} вместо #{finding.measurement.round(2)}"
        else "аэропорт в #{(value.to_f / 1000).round(1)} км вместо #{(finding.measurement / 1000).round(1)} км"
        end

      "Взять другой объект в этом же городе — «#{property.name}»: #{readable}. " \
        "Разницу в цене и в совпадении посчитает симуляция при применении."
    end

    def shift_dates(finding, evidence, future)
      target = better_month(finding, evidence)
      return nil unless target

      month, normal, after = target
      nights = (evidence.check_out - evidence.check_in).to_i
      shifted_in = shift(evidence.check_in, month)
      price = rate_difference(evidence, shifted_in, shifted_in + nights)
      return nil unless price

      {
        "id" => mitigation_id(future, finding, "shift_dates"),
        "description" => "Перенести поездку на #{Date::MONTHNAMES[month]}: норма #{normal.round(1)} °C " \
                         "вместо #{finding.measurement.round(1)} °C за те же #{nights} ночей.",
        "price_change" => price,
        "severity_after" => after
      }
    end

    def better_month(finding, evidence)
      current = evidence.months.first
      candidates = ((current - MONTH_WINDOW)..(current + MONTH_WINDOW)).map { |m| ((m - 1) % 12) + 1 }
      candidates -= evidence.months

      candidates.filter_map do |month|
        normals = Supply::Climate.normals(city_code: evidence.city_code, month: month) || {}
        mean = normals["temp_mean_c"]
        next if mean.nil?

        after = severity_with(finding, mean.to_f)
        next unless better?(after, Scoring.severity(finding))

        [month, mean.to_f, after]
      end.min_by { |month, _mean, after| [ORDER.index(after), (month - current).abs] }
    end

    def shift(date, month)
      offset = month - date.month
      offset += 12 if offset.negative?
      date >> offset
    end

    def price_difference(_future, evidence, alternative)
      current = rate(evidence.property_id, evidence.check_in, evidence.check_out)
      swapped = rate(alternative.catalogue_id, evidence.check_in, evidence.check_out)
      difference(current, swapped)
    end

    def rate_difference(evidence, check_in, check_out)
      current = rate(evidence.property_id, evidence.check_in, evidence.check_out)
      shifted = rate(evidence.property_id, check_in, check_out)
      difference(current, shifted)
    end

    def rate(property_id, check_in, check_out)
      Supply::Rates.for(property_id: property_id, check_in: check_in.to_s, check_out: check_out.to_s, adults: 2)
    rescue StandardError
      nil
    end

    def difference(current, other)
      from = current && current["amount"]
      to = other && other["amount"]
      return nil unless from && to && from["currency"] == to["currency"]

      { "amount_minor" => to["amount_minor"] - from["amount_minor"], "currency" => from["currency"] }
    end

    MAGNITUDE = { "low" => 0.15, "medium" => 0.25, "high" => 0.4 }.freeze

    def adjustment(finding, mitigation_id)
      dimension = mitigation_id.to_s.end_with?("shift_dates") ? "dates" : finding.affected_dimension
      { "dimension" => dimension, "direction" => "increase",
        "magnitude" => MAGNITUDE.fetch(Scoring.severity(finding)) }
    end

    def risk_id(future, finding) = "#{future["id"]}:#{finding.risk_type}"
    def mitigation_id(future, finding, kind) = "#{risk_id(future, finding)}:#{kind}"

    def parse_risk_id(risk_id)
      future_id, risk_type = risk_id.to_s.split(":", 2)
      [future_id, risk_type]
    end
  end
end
