# frozen_string_literal: true

class Robots
  # RobotsResult encapsulates the result of querying robots.txt for a user-agent
  #
  # Provides a check(url) method to test if specific URLs are allowed
  class RobotsResult
    def initialize(matcher:)
      @matcher = matcher
    end

    # Checks if a specific URL is allowed for this user-agent
    # Returns UrlCheckResult with allowed status, line number, and line text
    def check(url)
      @matcher.check_url(url)
    end
  end
end
