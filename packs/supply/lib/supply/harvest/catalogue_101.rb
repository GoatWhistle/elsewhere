module Supply
  module Harvest
    module Catalogue101
      HOST = "https://101hotels.com".freeze

      DISALLOWED = %w[/search /city /redirect /favorites /nearby/location /booking/order_form /app /mobile_app].freeze
      CATALOGUE_PREFIX = "/main/cities/".freeze

      MIN_INTERVAL_S = 4.0

      module_function

      def city_url(slug) = "#{HOST}#{CATALOGUE_PREFIX}#{slug}"
      def category_url(slug, category) = "#{HOST}#{CATALOGUE_PREFIX}#{slug}/#{category}"
      def property_url(path) = "#{HOST}#{path}"

      def allowed?(path)
        path.to_s.start_with?(CATALOGUE_PREFIX) && DISALLOWED.none? { |prefix| path.to_s.start_with?(prefix) }
      end

      def categories_on(html, slug)
        html.to_s.scan(/href="(#{Regexp.escape(CATALOGUE_PREFIX)}#{Regexp.escape(slug)}\/[a-z0-9_]+)"/)
            .flatten.uniq
            .reject { |path| path.end_with?(".html") }
            .map { |path| path.split("/").last }
      end
    end
  end
end
