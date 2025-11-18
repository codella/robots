# frozen_string_literal: true

module Robots
  # RobotsResult encapsulates the result of querying robots.txt for a user-agent
  #
  # Contains:
  # - sitemaps: array of unique sitemap URLs found in robots.txt
  # - crawl_delay: crawl delay in seconds for the user-agent (nil if not specified)
  # - check(url): method to check if a specific URL is allowed
  class RobotsResult
    attr_reader :sitemaps, :crawl_delay

    def initialize(sitemaps:, crawl_delay:, matcher:)
      @sitemaps = sitemaps
      @crawl_delay = crawl_delay
      @matcher = matcher
    end

    # Checks if a specific URL is allowed for this user-agent
    # Returns UrlCheckResult with allowed status, line number, and line text
    def check(url)
      @matcher.check_url(url)
    end
  end
end
