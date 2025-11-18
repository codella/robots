# frozen_string_literal: true

require_relative 'utilities'

module Robots
  # LineMetadata holds information about a parsed line
  class LineMetadata
    attr_accessor :is_empty, :has_comment, :is_comment, :has_directive,
                  :is_line_too_long, :is_missing_colon_separator

    def initialize
      @is_empty = false
      @has_comment = false
      @is_comment = false
      @has_directive = false
      @is_line_too_long = false
      @is_missing_colon_separator = false
    end
  end

  # A ParsedRobotsKey represents a key directive in robots.txt
  # It can parse text representation and represent them as an enumeration
  # for faster processing
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

    def parse(key)
      @key_text = nil

      if self.class.key_is_user_agent?(key)
        @type = USER_AGENT
      elsif self.class.key_is_allow?(key)
        @type = ALLOW
      elsif self.class.key_is_disallow?(key)
        @type = DISALLOW
      elsif self.class.key_is_sitemap?(key)
        @type = SITEMAP
      else
        @type = UNKNOWN
        @key_text = key
      end
    end

    def self.key_is_user_agent?(key)
      starts_with_ignore_case?(key, 'user-agent')
    end

    def self.key_is_allow?(key)
      starts_with_ignore_case?(key, 'allow')
    end

    def self.key_is_disallow?(key)
      starts_with_ignore_case?(key, 'disallow')
    end

    def self.key_is_sitemap?(key)
      starts_with_ignore_case?(key, 'sitemap')
    end

    def self.starts_with_ignore_case?(str, prefix)
      return false if str.nil? || str.empty?
      str.downcase.start_with?(prefix.downcase)
    end
  end

  # Main robots.txt parser
  class RobotsTxtParser
    # UTF-8 Byte Order Mark sequence (appears at start of some UTF-8 files)
    UTF_BOM = [0xEF, 0xBB, 0xBF].freeze

    # Line ending byte values
    LINE_FEED = 0x0A          # \n (LF - Unix line ending)
    CARRIAGE_RETURN = 0x0D    # \r (CR - old Mac line ending, part of CRLF on Windows)

    # Line length limits
    # Based on Internet Explorer's historical URL length limit
    BROWSER_MAX_URL_LENGTH = 2083
    # Safety multiplier to allow for long patterns in robots.txt
    LINE_LENGTH_SAFETY_FACTOR = 8
    MAX_LINE_LEN = BROWSER_MAX_URL_LENGTH * LINE_LENGTH_SAFETY_FACTOR

    def initialize(robots_body, handler)
      @robots_body = robots_body || ''
      @handler = handler
    end

    def parse
      line_buffer = String.new(capacity: MAX_LINE_LEN)
      line_too_long = false
      line_num = 0
      bom_position = 0
      previous_was_carriage_return = false

      @handler.handle_robots_start

      @robots_body.each_byte do |current_byte|
        # Skip UTF-8 BOM at start of file
        if reading_bom?(bom_position, current_byte)
          bom_position += 1
          next
        end
        bom_position = UTF_BOM.length  # Mark BOM as fully processed

        if line_ending?(current_byte)
          # Handle line ending (LF, CR, or CRLF)
          unless crlf_continuation?(line_buffer, previous_was_carriage_return, current_byte)
            line_num += 1
            parse_and_emit_line(line_num, line_buffer.dup, line_too_long)
            line_too_long = false
          end

          line_buffer.clear
          previous_was_carriage_return = (current_byte == CARRIAGE_RETURN)
        else
          # Regular character - add to line buffer if there's room
          if line_buffer.bytesize < MAX_LINE_LEN - 1
            line_buffer << current_byte.chr
          else
            line_too_long = true
          end
        end
      end

      # Process final line if any content remains
      line_num += 1
      parse_and_emit_line(line_num, line_buffer, line_too_long)

      @handler.handle_robots_end
    end

    # Checks if we're currently reading the UTF-8 BOM sequence
    def reading_bom?(bom_position, current_byte)
      bom_position < UTF_BOM.length && current_byte == UTF_BOM[bom_position]
    end

    # Checks if a byte is a line ending character (LF or CR)
    def line_ending?(byte)
      byte == LINE_FEED || byte == CARRIAGE_RETURN
    end

    # Checks if this is the LF part of a CRLF sequence (should not emit a new line)
    # Windows uses CRLF (\r\n), so we skip the LF when it follows CR with empty buffer
    def crlf_continuation?(line_buffer, previous_was_cr, current_byte)
      line_buffer.empty? && previous_was_cr && current_byte == LINE_FEED
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
      parsed_key.parse(key)

      if should_escape_pattern_value?(parsed_key)
        escaped_value = Utilities.maybe_escape_pattern(value)
        emit_key_value_to_handler(current_line, parsed_key, escaped_value)
      else
        emit_key_value_to_handler(current_line, parsed_key, value)
      end

      @handler.report_line_metadata(current_line, line_metadata)
    end

    # Extracts key-value pair from a robots.txt line
    # Standard format: <key>:<value>
    # Extension: also accepts <key> <value> (whitespace separator)
    def get_key_and_value_from(line, metadata)
      line = strip_comment(line, metadata)

      return [nil, nil] if handle_empty_line(line, metadata)

      separator_position = find_key_value_separator(line, metadata)
      return [nil, nil] unless separator_position

      extract_key_and_value(line, separator_position, metadata)
    end

    # Removes comment from line (everything after '#')
    def strip_comment(line, metadata)
      comment_index = line.index('#')
      if comment_index
        metadata.has_comment = true
        line = line[0...comment_index]
      end
      line.strip
    end

    # Marks metadata for empty lines and returns true if line is empty
    def handle_empty_line(line, metadata)
      return false unless line.empty?

      if metadata.has_comment
        metadata.is_comment = true
      else
        metadata.is_empty = true
      end
      true
    end

    # Finds the separator between key and value (standard ':' or whitespace)
    # Returns position of separator, or nil if no valid separator found
    def find_key_value_separator(line, metadata)
      # Standard separator is colon
      colon_position = line.index(':')
      return colon_position if colon_position

      # Extension: accept whitespace separator in limited cases
      find_whitespace_separator(line, metadata)
    end

    # Finds whitespace separator (extension for missing colons)
    # Only accepts if there are exactly two non-whitespace sequences
    def find_whitespace_separator(line, metadata)
      whitespace_position = line.index(/[ \t]/)
      return nil unless whitespace_position

      value_start = line.index(/[^ \t]/, whitespace_position)
      return nil unless value_start

      # Only accept if exactly two non-whitespace sequences (key and value)
      if line[value_start..].index(/[ \t]/)
        return nil  # More than two sequences, invalid
      end

      metadata.is_missing_colon_separator = true
      whitespace_position
    end

    # Extracts and validates key-value pair from line
    def extract_key_and_value(line, separator_position, metadata)
      key = line[0...separator_position].strip
      value = line[(separator_position + 1)..].strip

      return [nil, nil] if key.empty?

      metadata.has_directive = true
      [key, value]
    end

    # Determines if pattern escaping should be applied to the value
    # User-agent and sitemap values are not patterns, so they don't need escaping
    # Allow/Disallow values are path patterns that need percent-encoding normalization
    def should_escape_pattern_value?(key)
      case key.type
      when ParsedRobotsKey::USER_AGENT, ParsedRobotsKey::SITEMAP
        false  # These are literal strings, not patterns
      else
        true   # Allow/Disallow values are patterns that need escaping
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
