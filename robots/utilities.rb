# frozen_string_literal: true

class Robots
  module Utilities
    # Constants for percent-encoding
    HEX_DIGITS = '0123456789ABCDEF'

    # Constants for byte operations
    HIGH_BIT_MASK = 0x80       # Mask for detecting non-ASCII bytes (high bit set)
    NIBBLE_MASK = 0x0F         # Mask for extracting low 4 bits
    HIGH_NIBBLE_SHIFT = 4      # Bits to shift for high nibble

    # Extracts path (with params) and query part from URL. Removes scheme,
    # authority, and fragment. Result always starts with "/".
    # Returns "/" if the url doesn't have a path or is not valid.
    #
    # Examples:
    #   'http://example.com/path' => '/path'
    #   'http://example.com/path?query' => '/path?query'
    #   'http://example.com' => '/'
    #   '//example.com/path' => '/path'
    #   '/path?query#fragment' => '/path?query'
    def self.get_path_params_query(url)
      require 'uri'
      return '/' if url.nil? || url.empty?

      # Handle URLs without scheme by adding a dummy scheme
      url_to_parse = if url.start_with?('/')
                       # Path-only or protocol-relative URL
                       url.start_with?('//') ? "http:#{url}" : "http://dummy#{url}"
                     elsif url.include?('://')
                       # Has a scheme
                       url
                     else
                       # No scheme (e.g., 'example.com/path')
                       "http://#{url}"
                     end

      uri = URI.parse(url_to_parse)

      # Build path with query
      path = uri.path.to_s
      path = '/' if path.empty?
      path += "?#{uri.query}" if uri.query
      path
    rescue URI::InvalidURIError
      '/'
    end

    # Canonicalize the allowed/disallowed paths. For example:
    #     /SanJoséSellers ==> /SanJos%C3%A9Sellers
    #     %aa ==> %AA
    #
    # Performs two normalizations:
    # 1. Uppercases hex digits in existing percent-escapes (%2f -> %2F)
    # 2. Percent-escapes non-ASCII bytes (é -> %C3%A9)
    #
    # Returns the escaped pattern (may be the same as input if no changes needed)
    def self.maybe_escape_pattern(src)
      return src if src.nil? || src.empty?

      src = src.dup.force_encoding('BINARY')

      # Check if any changes needed and build result in one pass
      result = String.new(capacity: src.bytesize * 2)
      result.force_encoding('BINARY')
      needs_changes = false
      byte_index = 0

      while byte_index < src.bytesize
        byte = src.getbyte(byte_index)

        # Handle percent-escape sequences
        if src[byte_index] == '%' && byte_index + 2 < src.bytesize &&
           hex_digit?(src[byte_index + 1]) && hex_digit?(src[byte_index + 2])
          result << '%'
          hex1, hex2 = src[byte_index + 1], src[byte_index + 2]
          result << hex1.upcase << hex2.upcase
          needs_changes ||= (hex1 != hex1.upcase || hex2 != hex2.upcase)
          byte_index += 3
        # Handle non-ASCII bytes
        elsif (byte & HIGH_BIT_MASK) != 0
          result << '%' << HEX_DIGITS[(byte >> HIGH_NIBBLE_SHIFT) & NIBBLE_MASK] <<
                    HEX_DIGITS[byte & NIBBLE_MASK]
          needs_changes = true
          byte_index += 1
        # Normal ASCII character
        else
          result << src[byte_index]
          byte_index += 1
        end
      end

      needs_changes ? result.force_encoding('UTF-8') : src.force_encoding('UTF-8')
    end

    # Extract the matchable part of a user agent string, essentially stopping at
    # the first invalid character.
    #
    # Only characters [a-zA-Z_-] are allowed.
    # This extracts the product name only.
    #
    # Examples:
    #   'MyBot/2.1' => 'MyBot'
    #   'Mozilla-5' => 'Mozilla-'
    #   'Bot_Name' => 'Bot_Name'
    #   '123Bot' => '' (starts with invalid char)
    def self.extract_user_agent(user_agent)
      return '' if user_agent.nil? || user_agent.empty?

      invalid_pos = user_agent.index(/[^a-zA-Z_-]/)
      user_agent[0...(invalid_pos || user_agent.length)]
    end

    # Verifies that the given user agent is valid to be matched against
    # robots.txt. Valid user agent strings only contain the characters
    # [a-zA-Z_-].
    def self.valid_user_agent?(user_agent)
      !user_agent.nil? && !user_agent.empty? && user_agent !~ /[^a-zA-Z_-]/
    end

    private

    def self.hex_digit?(char)
      char.match?(/[0-9a-fA-F]/)
    end
  end
end
