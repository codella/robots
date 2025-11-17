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
#   matcher = Robots::RobotsMatcher.new
#   robots_txt = File.read('robots.txt')
#   allowed = matcher.allowed?(robots_txt, 'MyBot', 'https://example.com/page.html')
#
# The library uses a longest-match strategy for pattern matching, which means that
# in case of conflicting rules, the longest matching pattern wins. When patterns
# have the same length, Allow wins over Disallow.
#
# The library is NOT thread-safe. Create separate RobotsMatcher instances for
# concurrent use.
#
# For more information, see:
# - https://www.rfc-editor.org/rfc/rfc9309.html

require_relative 'robots/utilities'
require_relative 'robots/match_strategy'
require_relative 'robots/parser'
require_relative 'robots/matcher'

module Robots
  VERSION = '1.0.0'
end
