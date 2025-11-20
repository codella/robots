# frozen_string_literal: true

class Robots
  # Sitemap encapsulates a sitemap URL from robots.txt with its line number
  #
  # Sitemaps are ALWAYS GLOBAL (not user-agent specific) per RFC 9309 Section 2.3.5.
  # They inform search engines about sitemap locations but don't affect access control.
  #
  # Contains:
  # - url: the sitemap URL as specified in robots.txt
  # - line_number: line number where this sitemap was declared
  class Sitemap
    attr_reader :url, :line_number

    def initialize(url:, line_number:)
      @url = url
      @line_number = line_number
    end

    # For compatibility with array operations and comparison
    def ==(other)
      other.is_a?(Sitemap) &&
        url == other.url &&
        line_number == other.line_number
    end

    alias eql? ==

    def hash
      [url, line_number].hash
    end
  end
end
