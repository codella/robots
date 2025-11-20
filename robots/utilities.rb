# frozen_string_literal: true

class Robots
  module Utilities
    # Constants for percent-encoding
    HEX_DIGITS = '0123456789ABCDEF'
    PERCENT_ESCAPE_LENGTH = 3  # Length of '%XX' sequence
    ESCAPE_CHAR_COUNT = 2      # Number of hex digits after '%'

    # Constants for byte operations
    HIGH_BIT_MASK = 0x80       # Mask for detecting non-ASCII bytes (high bit set)
    NIBBLE_MASK = 0x0F         # Mask for extracting low 4 bits
    HIGH_NIBBLE_SHIFT = 4      # Bits to shift for high nibble

    # URL parsing constants
    PROTOCOL_SEPARATOR = '://'
    PROTOCOL_SEPARATOR_LENGTH = 3
    PATH_QUERY_PARAM_CHARS = /[\/\?;]/  # Characters that start path/query/params

    # User-agent validation
    VALID_USER_AGENT_CHARS = /[a-zA-Z_-]/

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
      return '/' if url.nil? || url.empty?

      search_start = skip_leading_slashes(url)
      protocol_end = find_protocol_end(url, search_start)
      path_start = find_path_start(url, protocol_end)

      return '/' unless path_start

      extract_path_component(url, path_start, search_start)
    end

    # Skips initial '//' if present (for protocol-relative URLs)
    def self.skip_leading_slashes(url)
      if url.length >= 2 && url[0] == '/' && url[1] == '/'
        2
      else
        0
      end
    end

    # Finds where the protocol ends (after '://'), or returns search_start if no protocol
    def self.find_protocol_end(url, search_start)
      early_path_index = url.index(PATH_QUERY_PARAM_CHARS, search_start)
      protocol_end_index = url.index(PROTOCOL_SEPARATOR, search_start)

      # If path/query/param starts before '://', then '://' is not a protocol separator
      if early_path_index && protocol_end_index && early_path_index < protocol_end_index
        protocol_end_index = nil
      end

      if protocol_end_index
        protocol_end_index + PROTOCOL_SEPARATOR_LENGTH
      else
        search_start
      end
    end

    # Finds where the path component starts (at '/', '?', or ';')
    def self.find_path_start(url, protocol_end)
      url.index(PATH_QUERY_PARAM_CHARS, protocol_end)
    end

    # Extracts the path component, removing fragments and ensuring it starts with '/'
    def self.extract_path_component(url, path_start, search_start)
      fragment_index = url.index('#', search_start)

      # Fragment before path means no valid path
      return '/' if fragment_index && fragment_index < path_start

      path_end = fragment_index || url.length

      # Ensure path starts with '/' (prepend if it starts with '?' or ';')
      if url[path_start] != '/'
        '/' + url[path_start...path_end]
      else
        url[path_start...path_end]
      end
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

      # Use binary encoding for byte-level operations
      src = src.dup.force_encoding('BINARY')

      # First pass: check if any changes are needed
      escape_info = scan_for_escape_needs(src)
      return src.force_encoding('UTF-8') unless escape_info[:needs_changes]

      # Second pass: build escaped string
      build_escaped_string(src, escape_info[:bytes_to_escape])
    end

    # Scans string to determine if escaping/normalization is needed
    def self.scan_for_escape_needs(src)
      bytes_to_escape = 0
      needs_capitalization = false
      byte_index = 0

      while byte_index < src.bytesize
        if percent_escape_at?(src, byte_index)
          # Check if hex digits need uppercasing
          if lowercase_hex_in_escape?(src, byte_index)
            needs_capitalization = true
          end
          byte_index += PERCENT_ESCAPE_LENGTH
        elsif non_ascii_byte?(src.getbyte(byte_index))
          bytes_to_escape += 1
          byte_index += 1
        else
          byte_index += 1
        end
      end

      {
        needs_changes: bytes_to_escape > 0 || needs_capitalization,
        bytes_to_escape: bytes_to_escape
      }
    end

    # Builds a new string with proper escaping and normalization
    def self.build_escaped_string(src, bytes_to_escape)
      # Pre-allocate space: each escaped byte becomes 3 chars (%XX)
      result = String.new(capacity: bytes_to_escape * 2 + src.bytesize)
      result.force_encoding('BINARY')
      byte_index = 0

      while byte_index < src.bytesize
        if percent_escape_at?(src, byte_index)
          # Normalize existing percent-escape to uppercase
          result << src[byte_index]
          result << src[byte_index + 1].upcase
          result << src[byte_index + 2].upcase
          byte_index += PERCENT_ESCAPE_LENGTH
        elsif non_ascii_byte?(src.getbyte(byte_index))
          # Percent-escape non-ASCII byte
          append_percent_escaped_byte(result, src.getbyte(byte_index))
          byte_index += 1
        else
          # Normal ASCII character, copy as-is
          result << src[byte_index]
          byte_index += 1
        end
      end

      result.force_encoding('UTF-8')
    end

    # Checks if there's a valid percent-escape sequence at the given position
    def self.percent_escape_at?(string, position)
      return false if position + ESCAPE_CHAR_COUNT >= string.bytesize
      string[position] == '%' &&
        hex_digit?(string[position + 1]) &&
        hex_digit?(string[position + 2])
    end

    # Checks if a percent-escape contains lowercase hex digits
    def self.lowercase_hex_in_escape?(string, position)
      string[position + 1].match?(/[a-f]/) || string[position + 2].match?(/[a-f]/)
    end

    # Checks if a byte value is non-ASCII (high bit set)
    def self.non_ascii_byte?(byte_value)
      (byte_value & HIGH_BIT_MASK) != 0
    end

    # Appends a percent-escaped byte to the result string (%XX format)
    def self.append_percent_escaped_byte(result, byte_value)
      result << '%'
      result << HEX_DIGITS[(byte_value >> HIGH_NIBBLE_SHIFT) & NIBBLE_MASK]
      result << HEX_DIGITS[byte_value & NIBBLE_MASK]
    end

    # Extract the matchable part of a user agent string, essentially stopping at
    # the first invalid character.
    #
    # Only characters in VALID_USER_AGENT_CHARS ([a-zA-Z_-]) are allowed.
    # This extracts the product name only.
    #
    # Examples:
    #   'MyBot/2.1' => 'MyBot'
    #   'Mozilla-5' => 'Mozilla-'
    #   'Bot_Name' => 'Bot_Name'
    #   '123Bot' => '' (starts with invalid char)
    def self.extract_user_agent(user_agent)
      return '' if user_agent.nil? || user_agent.empty?

      # Find first character that's not in VALID_USER_AGENT_CHARS
      invalid_char_position = user_agent.chars.find_index { |char| char !~ VALID_USER_AGENT_CHARS }

      # Extract up to first invalid character, or entire string if all valid
      end_position = invalid_char_position || user_agent.length
      user_agent[0...end_position]
    end

    # Verifies that the given user agent is valid to be matched against
    # robots.txt. Valid user agent strings only contain the characters
    # [a-zA-Z_-].
    def self.valid_user_agent?(user_agent)
      return false if user_agent.nil? || user_agent.empty?
      extract_user_agent(user_agent) == user_agent
    end

    private

    def self.hex_digit?(char)
      char.match?(/[0-9a-fA-F]/)
    end
  end
end
