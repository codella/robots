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
  #
  # Using Struct provides automatic equality, hash, and comparison methods
  Sitemap = Struct.new(:url, :line_number, keyword_init: true)
end
