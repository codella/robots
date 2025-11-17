# frozen_string_literal: true

module Robots
  module Utilities
    HEX_DIGITS = '0123456789ABCDEF'

    # Extracts path (with params) and query part from URL. Removes scheme,
    # authority, and fragment. Result always starts with "/".
    # Returns "/" if the url doesn't have a path or is not valid.
    def self.get_path_params_query(url)
      return '/' if url.nil? || url.empty?

      # Initial two slashes are ignored
      search_start = 0
      if url.length >= 2 && url[0] == '/' && url[1] == '/'
        search_start = 2
      end

      early_path_idx = url.index(/[\/\?;]/, search_start)
      protocol_end_idx = url.index('://', search_start)

      # If path, param or query starts before ://, :// doesn't indicate protocol
      if early_path_idx && protocol_end_idx && early_path_idx < protocol_end_idx
        protocol_end_idx = nil
      end

      protocol_end = if protocol_end_idx
                       protocol_end_idx + 3
                     else
                       search_start
                     end

      path_start_idx = url.index(/[\/\?;]/, protocol_end)
      if path_start_idx
        hash_idx = url.index('#', search_start)
        return '/' if hash_idx && hash_idx < path_start_idx

        path_end = hash_idx || url.length

        if url[path_start_idx] != '/'
          # Prepend a slash if the result would start e.g. with '?'
          return '/' + url[path_start_idx...path_end]
        end

        return url[path_start_idx...path_end]
      end

      '/'
    end

    # Canonicalize the allowed/disallowed paths. For example:
    #     /SanJoséSellers ==> /SanJos%C3%A9Sellers
    #     %aa ==> %AA
    # Returns the escaped pattern (may be the same as input if no changes needed)
    def self.maybe_escape_pattern(src)
      return src if src.nil? || src.empty?

      # Use binary encoding for byte operations
      src = src.dup.force_encoding('BINARY')
      num_to_escape = 0
      need_capitalize = false

      # First, scan the buffer to see if changes are needed. Most don't.
      i = 0
      while i < src.bytesize
        # (a) % escape sequence
        if src[i] == '%' && i + 2 < src.bytesize &&
           hex_digit?(src[i + 1]) && hex_digit?(src[i + 2])
          if src[i + 1].match?(/[a-f]/) || src[i + 2].match?(/[a-f]/)
            need_capitalize = true
          end
          i += 3
        # (b) needs escaping (high bit set - non-ASCII)
        elsif src.getbyte(i) & 0x80 != 0
          num_to_escape += 1
          i += 1
        else
          i += 1
        end
      end

      # Return if no changes needed
      return src.force_encoding('UTF-8') unless num_to_escape > 0 || need_capitalize

      # Build new string with escaping
      result = String.new(capacity: num_to_escape * 2 + src.bytesize)
      result.force_encoding('BINARY')

      i = 0
      while i < src.bytesize
        # (a) Normalize %-escaped sequence (eg. %2f -> %2F)
        if src[i] == '%' && i + 2 < src.bytesize &&
           hex_digit?(src[i + 1]) && hex_digit?(src[i + 2])
          result << src[i]
          result << src[i + 1].upcase
          result << src[i + 2].upcase
          i += 3
        # (b) %-escape octets whose highest bit is set. These are outside ASCII range.
        elsif src.getbyte(i) & 0x80 != 0
          byte = src.getbyte(i)
          result << '%'
          result << HEX_DIGITS[(byte >> 4) & 0xf]
          result << HEX_DIGITS[byte & 0xf]
          i += 1
        # (c) Normal character, no modification needed
        else
          result << src[i]
          i += 1
        end
      end

      result.force_encoding('UTF-8')
    end

    # Extract the matchable part of a user agent string, essentially stopping at
    # the first invalid character.
    # Example: 'Googlebot/2.1' becomes 'Googlebot'
    def self.extract_user_agent(user_agent)
      return '' if user_agent.nil? || user_agent.empty?

      # Allowed characters in user-agent are [a-zA-Z_-]
      end_idx = 0
      while end_idx < user_agent.length
        char = user_agent[end_idx]
        break unless char.match?(/[a-zA-Z_-]/)
        end_idx += 1
      end

      user_agent[0...end_idx]
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
