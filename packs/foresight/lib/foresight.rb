require "date"
require "time"
require_relative "../../shared/lib/elsewhere/values"
require_relative "../../supply/lib/supply"
require_relative "../../planning/lib/planning"
require_relative "foresight/evidence"
require_relative "foresight/rules/night_noise"
require_relative "foresight/rules/walkability"
require_relative "foresight/rules/weather_mismatch"
require_relative "foresight/rules/transfer_difficulty"
require_relative "foresight/rules"
require_relative "foresight/scoring"
require_relative "foresight/relevance"
require_relative "foresight/mitigations"

module Foresight
  module Forecasts
    ALL_RISK_TYPES = Elsewhere::Values::RISK_TYPES

    module_function

    def for_future(future_id:)
      future = Planning::Futures.find(future_id: future_id)
      evidence = Evidence.for_future(future)
      dna = Relevance.dna_for(future)

      {
        "future_id" => future_id,
        "generated_at" => Time.now.utc.iso8601,
        "risks" => risks(future, evidence, dna),
        "coverage" => coverage(evidence, dna: dna)
      }
    end

    def risks(future, evidence, dna)
      findings = Rules.findings(evidence, dna: dna).select(&:triggered?)
      Relevance.filter(findings, dna).map { |finding| risk_item(finding, evidence, future) }
    end

    def risk_item(finding, evidence = nil, future = {})
      {
        "id" => Mitigations.risk_id(future, finding),
        "risk_type" => finding.risk_type,
        "severity" => Scoring.severity(finding),
        "confidence" => Scoring.confidence(finding),
        "claim_kind" => finding.claim_kind,
        "affected_dimension" => finding.affected_dimension,
        "statement" => finding.statement,
        "evidence" => finding.evidence,
        "mitigations" => evidence ? Mitigations.for_finding(finding, evidence, future) : []
      }
    end

    DNA_UNRESOLVED_REASON = "Travel DNA could not be resolved; relevance filtering was not applied".freeze

    def coverage(evidence, dna: nil)
      ALL_RISK_TYPES.map do |risk_type|
        assessed = evidence.available?(risk_type)
        entry = { "risk_type" => risk_type, "assessed" => assessed }
        reasons = []
        reasons << evidence.unavailable_reason(risk_type) unless assessed
        reasons << DNA_UNRESOLVED_REASON unless dna
        entry["reason"] = reasons.join("; ") if reasons.any?
        entry
      end
    end

    def mitigation_adjustment(risk_id:, mitigation_id:)
      future_id, risk_type = Mitigations.parse_risk_id(risk_id)
      future = Planning::Futures.find(future_id: future_id)
      raise ArgumentError, "unknown future in risk id #{risk_id}" unless future

      evidence = Evidence.for_future(future)
      finding = Rules.findings(evidence, dna: Relevance.dna_for(future))
                     .find { |candidate| candidate.risk_type == risk_type }
      raise ArgumentError, "no #{risk_type} risk on future #{future_id}" unless finding

      Mitigations.adjustment(finding, mitigation_id)
    end
  end
end
