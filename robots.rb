# frozen_string_literal: true

# Robots.txt Parser and Matcher Library
#
# The Robots Exclusion Protocol (REP) is a standard that enables website owners to
# control which URLs may be accessed by automated clients (i.e. crawlers) through
# a simple text file with a specific syntax.
#
# This library is a Ruby port of a robots.txt parser and matcher,
# maintaining compatibility with standard implementations.
#
# Basic usage:
#   require 'robots'
#
#   robots_txt = File.read('robots.txt')
#   robots = Robots.new(robots_txt, 'MyBot')
#
#   # Check specific URLs
#   result = robots.check('https://example.com/page.html')
#   result.allowed        # => true/false (whether URL is allowed)
#   result.line_number    # => 2 (line in robots.txt that matched)
#   result.line_text      # => "Disallow: /admin/" (text of matching line)
#
# The library uses a longest-match strategy for pattern matching, which means that
# in case of conflicting rules, the longest matching pattern wins. When patterns
# have the same length, Allow wins over Disallow.
#
# The Robots instance is NOT thread-safe. Create separate instances for each thread.
# The returned UrlCheckResult should also not be shared across threads.
#
# For more information, see:
# - https://www.rfc-editor.org/rfc/rfc9309.html

require_relative 'robots/utilities'
require_relative 'robots/match_strategy'
require_relative 'robots/parser'
require_relative 'robots/url_check_result'
require_relative 'robots/result'
require_relative 'robots/matcher'

class Robots
  VERSION = '1.0.0'

  # Creates a new Robots instance for the given robots.txt content and user agent.
  #
  # Parses the robots.txt content and extracts rules relevant to the specified user agent.
  #
  # @param robots_body [String] The content of robots.txt
  # @param user_agent [String] The user agent to check rules for
  #
  # @example
  #   robots = Robots.new(robots_txt, 'MyBot')
  #   result = robots.check('https://example.com/page.html')
  def initialize(robots_body, user_agent)
    @matcher = RobotsMatcher.new
    @result = @matcher.query(robots_body, user_agent)
  end

  # Checks if a URL is allowed for the configured user agent.
  #
  # @param url [String] The URL to check
  # @return [UrlCheckResult] Result with allowed status, line number, and line text
  #
  # @example
  #   robots = Robots.new(robots_txt, 'MyBot')
  #   result = robots.check('https://example.com/page.html')
  #   puts result.allowed      # => true/false
  #   puts result.line_number  # => line number that matched
  #   puts result.line_text    # => text of matching line
  def check(url)
    @result.check(url)
  end
end
