# frozen_string_literal: true

module Robots
  # UrlCheckResult encapsulates the result of checking a single URL against robots.txt
  #
  # Contains:
  # - allowed: boolean indicating if the URL is allowed
  # - line_number: line number in robots.txt that matched (0 if no match)
  # - line_text: actual text of the matching line (empty string if no match)
  class UrlCheckResult
    attr_reader :allowed, :line_number, :line_text

    def initialize(allowed:, line_number: 0, line_text: '')
      @allowed = allowed
      @line_number = line_number
      @line_text = line_text
    end
  end
end
