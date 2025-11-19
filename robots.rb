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
#   result = Robots.query(robots_txt, 'MyBot')
#
#   # Check specific URLs
#   check = result.check('https://example.com/page.html')
#   check.allowed        # => true/false (whether URL is allowed)
#   check.line_number    # => 2 (line in robots.txt that matched)
#   check.line_text      # => "Disallow: /admin/" (text of matching line)
#
# The library uses a longest-match strategy for pattern matching, which means that
# in case of conflicting rules, the longest matching pattern wins. When patterns
# have the same length, Allow wins over Disallow.
#
# The library is NOT thread-safe. Each call to Robots.query creates a new matcher
# instance internally, making it safe to call from different threads. However,
# the returned RobotsResult should not be shared across threads.
#
# For more information, see:
# - https://www.rfc-editor.org/rfc/rfc9309.html

require_relative 'robots/utilities'
require_relative 'robots/match_strategy'
require_relative 'robots/parser'
require_relative 'robots/url_check_result'
require_relative 'robots/result'
require_relative 'robots/matcher'

module Robots
  VERSION = '1.0.0'

  # Queries robots.txt for the given user agent.
  #
  # This is the main entry point for the library. It returns a RobotsResult
  # with a check(url) method to test specific URLs.
  #
  # @param robots_body [String] The content of robots.txt
  # @param user_agent [String] The user agent to check rules for
  # @return [RobotsResult] Result object with check(url) method
  #
  # @example
  #   result = Robots.query(robots_txt, 'MyBot')
  #   check = result.check('https://example.com/page.html')
  #   puts check.allowed  # => true/false
  def self.query(robots_body, user_agent)
    matcher = RobotsMatcher.new
    matcher.query(robots_body, user_agent)
  end
end
