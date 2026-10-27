require "time"
require_relative "http"
require_relative "page_cache"
require_relative "harvest/microdata"
require_relative "harvest/catalogue_101"

module Supply
  module Harvest
    Summary = Struct.new(:pages_requested, :pages_from_cache, :pages_fetched, :properties_seen,
                         :properties_written, :destinations_written, :refusals, :errors, :stopped, :cities,
                         keyword_init: true) do
      def to_s
        "#{properties_written} properties in #{destinations_written} destinations · " \
          "#{pages_requested} pages (#{pages_from_cache} cached, #{pages_fetched} fetched) · " \
          "#{refusals} refused, #{errors} errored#{stopped ? " · STOPPED: #{stopped}" : ""}"
      end
    end

    City = Struct.new(:slug, :city_code, :name, :country, :geography_type, :peak_season, keyword_init: true)

    SOURCE = "101hotels".freeze

    module_function

    def run(cities:, categories: [], refresh: false, cache: PageCache.new, persist: true,
            offline: false, log: nil)
      summary = Summary.new(pages_requested: 0, pages_from_cache: 0, pages_fetched: 0, properties_seen: 0,
                            properties_written: 0, destinations_written: 0, refusals: 0, errors: 0,
                            stopped: nil, cities: [])

      cities.map { |city| coerce(city) }.each do |city|
        break if summary.stopped

        records = collect(city, categories, refresh, cache, offline, summary, log)
        next if records.empty?

        summary.properties_seen += records.length
        summary.cities << city.city_code
        next unless persist

        written = persist!(city, records, summary, log)
        summary.destinations_written += 1
        summary.properties_written += written
      end

      summary
    end

    def collect(city, categories, refresh, cache, offline, summary, log)
      landing = page(Catalogue101.city_url(city.slug), refresh, cache, offline, summary, log)
      return [] unless landing

      pages = [landing]
      available = Catalogue101.categories_on(landing, city.slug)
      (categories & available).each do |category|
        break if summary.stopped

        body = page(Catalogue101.category_url(city.slug, category), refresh, cache, offline, summary, log)
        pages << body if body
      end

      pages.flat_map { |body| Microdata.lodgings(body) }
           .reject { |record| record[:source_id].to_s.empty? }
           .uniq { |record| record[:source_id] }
    end

    def page(url, refresh, cache, offline, summary, log)
      path = URI.parse(url).path
      unless Catalogue101.allowed?(path)
        summary.errors += 1
        log&.call("skipped (robots.txt disallows): #{path}")
        return nil
      end

      summary.pages_requested += 1
      entry = cache.fetch(url, refresh: refresh) do
        if offline
          summary.errors += 1
          log&.call("not cached, and offline: #{path}")
          next nil
        end

        response = Http.get(url, timeout: 30, min_interval: Catalogue101::MIN_INTERVAL_S)

        if response.refused?
          summary.refusals += 1
          summary.stopped = "#{response.status} from #{URI.parse(url).host} — the source is refusing us"
          log&.call(summary.stopped)
          next nil
        end

        unless response.ok?
          summary.errors += 1
          log&.call("#{response.status || response.error} #{path}")
          next nil
        end

        cache.write(url, status: response.status, body: response.body)
      end
      return nil unless entry

      entry.from_cache? ? summary.pages_from_cache += 1 : summary.pages_fetched += 1
      log&.call("#{entry.from_cache? ? "cache" : "fetch"} #{path}")
      entry.body
    end

    def persist!(city, records, summary = nil, log = nil)
      harvested_at = Time.now.utc
      points = records.map { |record| [record[:lat].to_f, record[:lon].to_f] }

      destination = DestinationRecord.find_or_initialize_by(city_code: city.city_code)
      destination.assign_attributes(
        name: city.name, country: city.country, source: SOURCE, source_slug: city.slug,
        geography_type: city.geography_type, peak_season: city.peak_season
      )

      if destination.centre_source.nil? || destination.centre_source == "property_centroid"
        destination.assign_attributes(lat: median(points.map(&:first)), lon: median(points.map(&:last)),
                                      centre_source: "property_centroid")
      end
      destination.save!

      records.count do |record|
        guarded(summary, log, "#{SOURCE}:#{record[:source_id]}") { upsert_property(destination, city, record, harvested_at) }
      end
    end

    def guarded(summary, log, what)
      yield
    rescue StandardError => e
      summary.errors += 1 if summary
      log&.call("skipped #{what}: #{e.class}: #{e.message}")
      false
    end

    def upsert_property(destination, city, record, harvested_at)
      rating, rating_scale = Microdata.rating(record)
      price_level_minor, price_level_note = Microdata.price_level(record)
      property = PropertyRecord.find_or_initialize_by(catalogue_id: "#{SOURCE}:#{record[:source_id]}")
      property.assign_attributes(
        source: SOURCE, destination_id: destination.id, city_code: city.city_code,
        name: record[:name], lat: record[:lat], lon: record[:lon], address: record[:address],
        rating: rating, rating_scale: rating_scale, review_count: record[:review_count]&.to_i,
        price_level_minor: price_level_minor, price_level_note: price_level_note,
        price_currency: (record[:price_currency] || "RUB"),
        price_level_text: record[:price_level_text],
        photos: record[:photos], harvested_at: harvested_at,
        source_url: record[:path] ? Catalogue101.property_url(record[:path]) : Catalogue101.city_url(city.slug)
      )
      property.save!
      true
    end

    def median(values)
      sorted = values.compact.sort
      return 0.0 if sorted.empty?

      middle = sorted.length / 2
      sorted.length.odd? ? sorted[middle] : ((sorted[middle - 1] + sorted[middle]) / 2.0)
    end

    def coerce(city)
      return city if city.is_a?(City)

      attributes = city.transform_keys(&:to_sym)
      City.new(slug: attributes.fetch(:slug), city_code: attributes.fetch(:city_code),
               name: attributes.fetch(:name), country: attributes.fetch(:country, "RU"),
               geography_type: attributes[:geography_type], peak_season: attributes[:peak_season])
    end
  end
end
