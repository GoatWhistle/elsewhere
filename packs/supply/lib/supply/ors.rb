require "json"
require_relative "http"

module Supply
  module Ors
    NO_KEY = "ORS_API_KEY is not set — the walk isochrone and the transfer time were not requested".freeze

    Answer = Struct.new(:value, :reason, keyword_init: true) do
      def assessed? = reason.nil?
    end

    module_function

    def key = ENV["ORS_API_KEY"].to_s.strip
    def configured? = !key.empty?
    def base = ENV.fetch("ORS_BASE_URL", "https://api.openrouteservice.org")

    def walk_isochrone_m2(lat:, lon:, minutes: 10)
      return Answer.new(reason: NO_KEY) unless configured?

      response = Http.post_json("#{base}/v2/isochrones/foot-walking",
                                { "locations" => [[lon.to_f, lat.to_f]], "range" => [minutes * 60],
                                  "range_type" => "time", "attributes" => ["area"] },
                                headers: { "Authorization" => key }, timeout: 60, min_interval: 1.5)
      return Answer.new(reason: "ORS isochrone: #{response.error || "HTTP #{response.status}"}") unless response.ok?

      area = response.json&.dig("features", 0, "properties", "area")
      area ? Answer.new(value: area.round) : Answer.new(reason: "ORS isochrone returned no area")
    end

    def transfer_minutes(from:, to:)
      return Answer.new(reason: NO_KEY) unless configured?

      response = Http.post_json("#{base}/v2/matrix/driving-car",
                                { "locations" => [[from[:lon].to_f, from[:lat].to_f], [to[:lon].to_f, to[:lat].to_f]],
                                  "sources" => [0], "destinations" => [1], "metrics" => ["duration"] },
                                headers: { "Authorization" => key }, timeout: 60, min_interval: 1.5)
      return Answer.new(reason: "ORS matrix: #{response.error || "HTTP #{response.status}"}") unless response.ok?

      seconds = response.json&.dig("durations", 0, 0)
      seconds ? Answer.new(value: (seconds / 60.0).round) : Answer.new(reason: "ORS matrix returned no duration")
    end
  end
end
