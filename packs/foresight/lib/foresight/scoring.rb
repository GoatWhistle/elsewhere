module Foresight
  module Scoring
    LOW_BAND_MAX = 0.25
    MEDIUM_BAND_MAX = 0.60

    BY_CLAIM_KIND = { "verified_fact" => 0.9, "derived_metric" => 0.75, "model_inference" => 0.5 }.freeze

    module_function

    def severity(finding)
      exceedance = finding.exceedance.to_f

      case exceedance
      when ..LOW_BAND_MAX then "low"
      when ..MEDIUM_BAND_MAX then "medium"
      else "high"
      end
    end

    def confidence(finding)
      base = BY_CLAIM_KIND.fetch(finding.claim_kind)
      (base * completeness(finding)).round(2)
    end

    def completeness(finding)
      value = finding.completeness
      return 1.0 if value.nil?

      value.to_f.clamp(0.0, 1.0)
    end
  end
end
