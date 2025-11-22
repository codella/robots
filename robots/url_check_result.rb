# frozen_string_literal: true

class Robots
  # UrlCheckResult encapsulates the result of checking a single URL against robots.txt
  #
  # Contains:
  # - allowed: boolean indicating if the URL is allowed (access via allowed?)
  # - line_number: line number in robots.txt that matched (0 if no match)
  # - line_text: actual text of the matching line (empty string if no match)
  UrlCheckResult = Struct.new(:allowed, :line_number, :line_text, keyword_init: true) do
    # Predicate method for checking if URL is allowed
    def allowed?
      allowed
    end

    # Provide default values
    def initialize(allowed:, line_number: 0, line_text: '')
      super(allowed: allowed, line_number: line_number, line_text: line_text)
    end
  end
end
