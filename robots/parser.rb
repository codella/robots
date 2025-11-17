# frozen_string_literal: true

require_relative 'utilities'

module Robots
  # Allow for typos such as DISALOW in robots.txt
  ALLOW_FREQUENT_TYPOS = true

  # LineMetadata holds information about a parsed line
  class LineMetadata
    attr_accessor :is_empty, :has_comment, :is_comment, :has_directive,
                  :is_acceptable_typo, :is_line_too_long, :is_missing_colon_separator

    def initialize
      @is_empty = false
      @has_comment = false
      @is_comment = false
      @has_directive = false
      @is_acceptable_typo = false
      @is_line_too_long = false
      @is_missing_colon_separator = false
    end
  end

  # A ParsedRobotsKey represents a key directive in robots.txt
  # It can parse text representation (including common typos) and represent
  # them as an enumeration for faster processing
  class ParsedRobotsKey
    USER_AGENT = :user_agent
    SITEMAP = :sitemap
    ALLOW = :allow
    DISALLOW = :disallow
    UNKNOWN = :unknown

    attr_reader :type, :key_text

    def initialize
      @type = UNKNOWN
      @key_text = nil
    end

    def parse(key, is_acceptable_typo_ref)
      @key_text = nil
      is_acceptable_typo = false

      if self.class.key_is_user_agent?(key, is_acceptable_typo)
        @type = USER_AGENT
        is_acceptable_typo_ref[:value] = is_acceptable_typo
      elsif self.class.key_is_allow?(key, is_acceptable_typo)
        @type = ALLOW
        is_acceptable_typo_ref[:value] = is_acceptable_typo
      elsif self.class.key_is_disallow?(key, is_acceptable_typo)
        @type = DISALLOW
        is_acceptable_typo_ref[:value] = is_acceptable_typo
      elsif self.class.key_is_sitemap?(key, is_acceptable_typo)
        @type = SITEMAP
        is_acceptable_typo_ref[:value] = is_acceptable_typo
      else
        @type = UNKNOWN
        @key_text = key
        is_acceptable_typo_ref[:value] = false
      end
    end

    def self.key_is_user_agent?(key, is_typo)
      is_typo = ALLOW_FREQUENT_TYPOS && (
        starts_with_ignore_case?(key, 'useragent') ||
        starts_with_ignore_case?(key, 'user agent')
      )
      starts_with_ignore_case?(key, 'user-agent') || is_typo
    end

    def self.key_is_allow?(key, is_typo)
      # We don't support typos for the "allow" key
      is_typo = false
      starts_with_ignore_case?(key, 'allow')
    end

    def self.key_is_disallow?(key, is_typo)
      is_typo = ALLOW_FREQUENT_TYPOS && (
        starts_with_ignore_case?(key, 'dissallow') ||
        starts_with_ignore_case?(key, 'dissalow') ||
        starts_with_ignore_case?(key, 'disalow') ||
        starts_with_ignore_case?(key, 'diasllow') ||
        starts_with_ignore_case?(key, 'disallaw')
      )
      starts_with_ignore_case?(key, 'disallow') || is_typo
    end

    def self.key_is_sitemap?(key, is_typo)
      is_typo = ALLOW_FREQUENT_TYPOS && starts_with_ignore_case?(key, 'site-map')
      starts_with_ignore_case?(key, 'sitemap') || is_typo
    end

    def self.starts_with_ignore_case?(str, prefix)
      return false if str.nil? || str.empty?
      str.downcase.start_with?(prefix.downcase)
    end
  end

  # Handler interface for parsing callbacks
  class RobotsParseHandler
    def handle_robots_start; end
    def handle_robots_end; end
    def handle_user_agent(line_num, value); end
    def handle_allow(line_num, value); end
    def handle_disallow(line_num, value); end
    def handle_sitemap(line_num, value); end
    def handle_unknown_action(line_num, action, value); end
    def report_line_metadata(line_num, metadata); end
  end

  # Main robots.txt parser
  class RobotsTxtParser
    # UTF-8 byte order marks
    UTF_BOM = [0xEF, 0xBB, 0xBF].freeze

    # Line length limits (browsers limit URLs to 2083 bytes, we allow 8x for safety)
    BROWSER_MAX_LINE_LEN = 2083
    MAX_LINE_LEN = BROWSER_MAX_LINE_LEN * 8

    def initialize(robots_body, handler)
      @robots_body = robots_body || ''
      @handler = handler
    end

    def parse
      line_buffer = String.new(capacity: MAX_LINE_LEN)
      line_too_long_strict = false
      line_num = 0
      bom_pos = 0
      last_was_carriage_return = false

      @handler.handle_robots_start

      @robots_body.each_byte do |ch|
        # Skip UTF-8 BOM if present at start
        if bom_pos < UTF_BOM.length && ch == UTF_BOM[bom_pos]
          bom_pos += 1
          next
        end
        bom_pos = UTF_BOM.length

        # Non-line-ending char case
        if ch != 0x0A && ch != 0x0D
          # Put in next spot on current line, as long as there's room
          if line_buffer.bytesize < MAX_LINE_LEN - 1
            line_buffer << ch.chr
          else
            line_too_long_strict = true
          end
        else
          # Line-ending character case
          # Only emit an empty line if this was not due to the second character
          # of the DOS line-ending \r\n
          is_crlf_continuation = line_buffer.empty? && last_was_carriage_return && ch == 0x0A

          unless is_crlf_continuation
            line_num += 1
            parse_and_emit_line(line_num, line_buffer.dup, line_too_long_strict)
            line_too_long_strict = false
          end

          line_buffer.clear
          last_was_carriage_return = (ch == 0x0D)
        end
      end

      # Process final line if any
      line_num += 1
      parse_and_emit_line(line_num, line_buffer, line_too_long_strict)

      @handler.handle_robots_end
    end

    private

    def parse_and_emit_line(current_line, line, line_too_long_strict)
      line_metadata = LineMetadata.new
      key, value = get_key_and_value_from(line, line_metadata)
      line_metadata.is_line_too_long = line_too_long_strict

      unless line_metadata.has_directive
        @handler.report_line_metadata(current_line, line_metadata)
        return
      end

      parsed_key = ParsedRobotsKey.new
      is_typo_ref = { value: false }
      parsed_key.parse(key, is_typo_ref)
      line_metadata.is_acceptable_typo = is_typo_ref[:value]

      if need_escape_value_for_key?(parsed_key)
        escaped_value = Utilities.maybe_escape_pattern(value)
        emit_key_value_to_handler(current_line, parsed_key, escaped_value)
      else
        emit_key_value_to_handler(current_line, parsed_key, value)
      end

      @handler.report_line_metadata(current_line, line_metadata)
    end

    def get_key_and_value_from(line, metadata)
      # Remove comments from the current robots.txt line
      comment_idx = line.index('#')
      if comment_idx
        metadata.has_comment = true
        line = line[0...comment_idx]
      end

      line = line.strip

      # If the line became empty after removing the comment, return
      if line.empty?
        if metadata.has_comment
          metadata.is_comment = true
        else
          metadata.is_empty = true
        end
        return [nil, nil]
      end

      # Rules must match the following pattern: <key>[ \t]*:[ \t]*<value>
      sep_idx = line.index(':')

      if sep_idx.nil?
        # Google-specific optimization: some people forget the colon, so we need to
        # accept whitespace in its stead
        sep_idx = line.index(/[ \t]/)
        if sep_idx
          val_start = line.index(/[^ \t]/, sep_idx)
          if val_start && line[val_start..].index(/[ \t]/)
            # We only accept whitespace as a separator if there are exactly two
            # sequences of non-whitespace characters
            return [nil, nil]
          end
          metadata.is_missing_colon_separator = true if val_start
        end
      end

      return [nil, nil] if sep_idx.nil?

      key = line[0...sep_idx].strip
      value = line[(sep_idx + 1)..].strip

      if key.empty?
        return [nil, nil]
      end

      metadata.has_directive = true
      [key, value]
    end

    def need_escape_value_for_key?(key)
      case key.type
      when ParsedRobotsKey::USER_AGENT, ParsedRobotsKey::SITEMAP
        false
      else
        true
      end
    end

    def emit_key_value_to_handler(line, key, value)
      case key.type
      when ParsedRobotsKey::USER_AGENT
        @handler.handle_user_agent(line, value)
      when ParsedRobotsKey::ALLOW
        @handler.handle_allow(line, value)
      when ParsedRobotsKey::DISALLOW
        @handler.handle_disallow(line, value)
      when ParsedRobotsKey::SITEMAP
        @handler.handle_sitemap(line, value)
      when ParsedRobotsKey::UNKNOWN
        @handler.handle_unknown_action(line, key.key_text, value)
      end
    end
  end

  # Main entry point for parsing robots.txt
  def self.parse_robots_txt(robots_body, parse_callback)
    parser = RobotsTxtParser.new(robots_body, parse_callback)
    parser.parse
  end
end
