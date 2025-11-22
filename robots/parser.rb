# frozen_string_literal: true

require_relative 'utilities'

class Robots
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
    CRAWL_DELAY = :crawl_delay
    UNKNOWN = :unknown

    # Hash-based lookup for directive prefixes (more maintainable than cascading if/elsif)
    DIRECTIVE_MAP = {
      'user-agent' => USER_AGENT,
      'allow' => ALLOW,
      'disallow' => DISALLOW,
      'sitemap' => SITEMAP,
      'crawl-delay' => CRAWL_DELAY
    }.freeze

    attr_reader :type, :key_text

    def initialize
      @type = UNKNOWN
      @key_text = nil
    end

    def parse(key)
      @key_text = nil
      key_lower = key&.downcase || ''

      # Find directive by prefix match using hash lookup
      @type = DIRECTIVE_MAP.find { |prefix, _| key_lower.start_with?(prefix) }&.last || begin
        @key_text = key
        UNKNOWN
      end
    end
  end

  # Main robots.txt parser
  class RobotsTxtParser
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
      @handler.handle_robots_start

      # Remove UTF-8 BOM if present (check bytes to avoid encoding issues)
      content = @robots_body
      bytes = content.bytes
      if bytes[0..2] == [0xEF, 0xBB, 0xBF]
        content = content.byteslice(3..-1) || ''
      end

      # Split on any line ending format (LF, CR, CRLF)
      lines = content.split(/\r\n|\r|\n/, -1)

      lines.each_with_index do |line, index|
        line_num = index + 1
        line_too_long = line.bytesize >= MAX_LINE_LEN
        parse_and_emit_line(line_num, line, line_too_long)
      end

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

      metadata.is_comment = metadata.has_comment
      metadata.is_empty = !metadata.has_comment
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
      ![ParsedRobotsKey::USER_AGENT, ParsedRobotsKey::SITEMAP].include?(key.type)
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
      when ParsedRobotsKey::CRAWL_DELAY
        @handler.handle_crawl_delay(line, value)
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
