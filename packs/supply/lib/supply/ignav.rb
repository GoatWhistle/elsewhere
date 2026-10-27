require "json"
require "cgi"
require "date"
require_relative "http"
require_relative "page_cache"

module Supply
  module Ignav
    Result = Struct.new(:itineraries, :airports, :links, :as_of, :from_cache, :reason, keyword_init: true) do
      def ok? = reason.nil?
    end

    module_function

    def key = ENV["IGNAV_API_KEY"].to_s.strip
    def configured? = !key.empty?
    def base = ENV.fetch("IGNAV_BASE_URL", "https://ignav.com/api")

    NO_KEY = "IGNAV_API_KEY is not set".freeze

    def airports(query, cache: PageCache.new, offline: false)
      body = get("#{base}/airports?q=#{CGI.escape(query.to_s)}&limit=10", cache: cache, offline: offline)
      return body if body.is_a?(Result)

      Result.new(airports: body.first, as_of: body.last, from_cache: body[1])
    end

    def one_way(origin:, destination:, depart_on:, adults: 1, cabin_class: "economy", market: nil,
                cache: PageCache.new, offline: false)
      fares("#{base}/fares/one-way",
            { "origin" => origin, "destination" => destination, "departure_date" => depart_on.to_s,
              "adults" => adults, "cabin_class" => cabin_class }.compact.merge(market ? { "market" => market } : {}),
            cache: cache, offline: offline)
    end

    def round_trip(origin:, destination:, depart_on:, return_on:, adults: 1, cabin_class: "economy", market: nil,
                   cache: PageCache.new, offline: false)
      fares("#{base}/fares/round-trip",
            { "origin" => origin, "destination" => destination, "departure_date" => depart_on.to_s,
              "return_date" => return_on.to_s, "adults" => adults, "cabin_class" => cabin_class }
              .merge(market ? { "market" => market } : {}),
            cache: cache, offline: offline)
    end

    def booking_links(ignav_id, cache: PageCache.new, offline: false)
      body = post("#{base}/fares/booking-links", { "ignav_id" => ignav_id }, cache: cache, offline: offline)
      return body if body.is_a?(Result)

      Result.new(links: body.first["booking_options"] || [], as_of: body.last, from_cache: body[1])
    end

    def fares(url, payload, cache:, offline:)
      body = post(url, payload, cache: cache, offline: offline)
      return body if body.is_a?(Result)

      Result.new(itineraries: body.first["itineraries"] || [], as_of: body.last, from_cache: body[1])
    end

    def get(url, cache:, offline:)
      fetch(url, cache: cache, offline: offline) { Http.get(url, headers: auth, timeout: 60, min_interval: 0.5) }
    end

    def post(url, payload, cache:, offline:)
      key_url = "#{url}?#{URI.encode_www_form(payload.sort_by { |name, _| name.to_s })}"
      fetch(key_url, cache: cache, offline: offline) do
        Http.post_json(url, payload, headers: auth, timeout: 90, min_interval: 0.5)
      end
    end

    def fetch(cache_key, cache:, offline:)
      failure = nil
      entry = cache.fetch(cache_key) do
        next nil if offline

        unless configured?
          failure = NO_KEY
          next nil
        end

        response = yield
        unless response.ok?
          failure = response.json&.dig("error", "message") || response.error || "HTTP #{response.status}"
          next nil
        end

        cache.write(cache_key, status: response.status, body: response.body)
      end
      return Result.new(reason: failure || (offline ? "not cached, and offline" : "no answer from Ignav")) if entry.nil?

      [JSON.parse(entry.body), entry.from_cache?, entry.fetched_at]
    rescue JSON::ParserError => e
      Result.new(reason: "unparseable Ignav answer: #{e.message}")
    end

    def auth = { "X-Api-Key" => key }
  end
end
