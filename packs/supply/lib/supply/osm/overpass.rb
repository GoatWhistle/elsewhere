require "json"
require "cgi"
require_relative "../http"
require_relative "../page_cache"

module Supply
  module Osm
    module Overpass
      ENDPOINT = "https://overpass-api.de/api/interpreter".freeze
      STATUS = "https://overpass-api.de/api/status".freeze

      MIN_INTERVAL_S = 12.0

      Result = Struct.new(:elements, :from_cache, :error, keyword_init: true) do
        def ok? = error.nil?
      end

      module_function

      def query(overpass_ql, cache: PageCache.new, refresh: false, offline: false)
        url = "#{ENDPOINT}?data=#{CGI.escape(overpass_ql)}"

        failure = nil
        entry = cache.fetch(url, refresh: refresh) do
          next nil if offline

          response = with_slot { Http.post_form(ENDPOINT, { "data" => overpass_ql }, timeout: 300, min_interval: MIN_INTERVAL_S) }
          unless response.ok?
            failure = response.error || "HTTP #{response.status}: #{response.body.to_s[/<p><strong[^>]*>Error<\/strong>:([^<]*)/, 1]&.strip || response.body.to_s[0, 120]}"
            next nil
          end

          cache.write(url, status: response.status, body: response.body)
        end

        return Result.new(elements: [], error: "not cached, and offline") if entry.nil? && offline
        return Result.new(elements: [], error: failure || "no answer from Overpass") if entry.nil?

        parsed = JSON.parse(entry.body)
        Result.new(elements: parsed.fetch("elements", []), from_cache: entry.from_cache?)
      rescue JSON::ParserError => e
        Result.new(elements: [], error: "unparseable Overpass answer: #{e.message}")
      end

      BUSY = [429, 502, 503, 504].freeze

      def with_slot(attempts: 3)
        attempts.times do |attempt|
          response = yield
          return response unless BUSY.include?(response.status)
          return response if attempt == attempts - 1

          wait = response.status == 429 ? seconds_until_slot : 45
          warn("overpass: busy (#{response.status}), waiting #{wait}s")
          sleep(wait)
        end
      end

      def seconds_until_slot(default: 30)
        status = Http.get(STATUS, timeout: 20, min_interval: 0)
        return default unless status.ok?

        seconds = status.body.to_s.scan(/Slot available after:.*?in (\d+) seconds/).flatten.map(&:to_i).min
        seconds ? seconds + 2 : default
      end

      def bbox(south, west, north, east) = format("%.5f,%.5f,%.5f,%.5f", south, west, north, east)
    end
  end
end
