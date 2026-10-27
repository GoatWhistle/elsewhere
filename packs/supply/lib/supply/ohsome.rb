require "json"
require_relative "http"

module Supply
  module Ohsome
    BASE = "https://api.ohsome.org/v1".freeze

    Answer = Struct.new(:features, :reason, keyword_init: true) do
      def assessed? = reason.nil?
    end

    module_function

    def base = ENV.fetch("OHSOME_BASE_URL", BASE)

    def coastline_count(west:, south:, east:, north:, on: Date.today.prev_month.to_s)
      response = Http.post_form("#{base}/elements/count",
                                { "bboxes" => format("%.6f,%.6f,%.6f,%.6f", west, south, east, north),
                                  "filter" => "natural=coastline and type:way", "time" => on },
                                timeout: 60, min_interval: 2.0)
      return Answer.new(reason: response.error || "HTTP #{response.status}") unless response.ok?

      value = response.json&.dig("result", 0, "value")
      value ? Answer.new(features: value.to_i) : Answer.new(reason: "ohsome returned no result")
    end
  end
end
