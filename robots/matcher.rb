# frozen_string_literal: true

require_relative 'parser'
require_relative 'match_strategy'
require_relative 'utilities'

class Robots
  # Represents a single rule from robots.txt
  class Rule
    attr_reader :pattern, :type, :is_global, :line_number

    def initialize(pattern:, type:, is_global:, line_number:)
      @pattern = pattern
      @type = type  # :allow or :disallow
      @is_global = is_global
      @line_number = line_number
    end
  end

  # RobotsMatcher - matches robots.txt against URLs
  #
  # The Matcher uses a default match strategy for Allow/Disallow patterns which
  # is the standard way to match robots.txt.
  #
  # The entry point for the user is to call query(robots_txt, user_agent) which returns
  # a RobotsResult. Call check(url) on the result to test specific URLs.
  # The RobotsMatcher can be re-used for URLs/robots.txt but is NOT thread-safe.
  class RobotsMatcher
    # Wildcard user-agent that matches all crawlers
    WILDCARD_AGENT = '*'
    WILDCARD_MIN_LENGTH = 1

    # Optimization: "/index.html" and "/index.htm" normalize to "/"
    INDEX_HTML_PATTERN = '/index.htm'

    # Match priority constant
    NO_MATCH_PRIORITY = -1

    def initialize
      # Parsed rules stored after initial parse (parse once, reuse many times)
      @rules = []
      @found_specific_agent = false

      # Tracks if current user-agent block includes the wildcard (*) agent
      @current_block_has_global_agent = false

      # Tracks if current user-agent block matches our target agent
      @current_block_matches_target_agent = false

      # Tracks if ANY block in the file matched our target agent
      # (important for determining whether to fall back to global rules)
      @found_matching_agent_section = false

      # Tracks if we've seen Allow/Disallow directives after user-agent declarations
      # (signals transition from user-agent declarations to rules)
      @current_block_has_rules = false

      @user_agent = nil
      @match_strategy = LongestMatchRobotsMatchStrategy.new

      # Robots.txt content split into lines for line text retrieval
      @robots_txt_lines = []
    end

    # Checks a specific URL against the parsed robots.txt rules
    # Returns UrlCheckResult with allowed status, line number, and line text
    def check_url(url)
      path = Utilities.get_path_params_query(url)

      # Match path against stored rules (no reparsing needed!)
      best_match = match_path_against_rules(path)

      allowed = best_match[:allowed]
      line = best_match[:line_number]
      line_text = get_line_text(line)

      UrlCheckResult.new(
        allowed: allowed,
        line_number: line,
        line_text: line_text
      )
    end

    # Matches a path against stored rules using longest-match strategy
    # Returns hash with :allowed and :line_number
    def match_path_against_rules(path)
      best_allow = { priority: NO_MATCH_PRIORITY, line_number: 0, is_global: false }
      best_disallow = { priority: NO_MATCH_PRIORITY, line_number: 0, is_global: false }

      # Check all rules and find best matches
      @rules.each do |rule|
        priority = @match_strategy.match_allow(path, rule.pattern)
        next if priority < 0  # No match

        if rule.type == :allow
          if priority > best_allow[:priority] ||
             (priority == best_allow[:priority] && !rule.is_global && best_allow[:is_global])
            best_allow = { priority: priority, line_number: rule.line_number, is_global: rule.is_global }
          end
        else  # :disallow
          if priority > best_disallow[:priority] ||
             (priority == best_disallow[:priority] && !rule.is_global && best_disallow[:is_global])
            best_disallow = { priority: priority, line_number: rule.line_number, is_global: rule.is_global }
          end
        end
      end

      # Apply decision logic based on RFC 9309 priority rules
      specific_allow = best_allow[:is_global] ? nil : best_allow
      specific_disallow = best_disallow[:is_global] ? nil : best_disallow
      global_allow = best_allow[:is_global] ? best_allow : nil
      global_disallow = best_disallow[:is_global] ? best_disallow : nil

      # Check agent-specific rules first (highest priority)
      if specific_allow && specific_allow[:priority] > NO_MATCH_PRIORITY ||
         specific_disallow && specific_disallow[:priority] > NO_MATCH_PRIORITY
        # Longer pattern wins; if equal, allow wins
        if specific_disallow && specific_disallow[:priority] > (specific_allow&.dig(:priority) || NO_MATCH_PRIORITY)
          return { allowed: false, line_number: specific_disallow[:line_number] }
        elsif specific_allow && specific_allow[:priority] > NO_MATCH_PRIORITY
          return { allowed: true, line_number: specific_allow[:line_number] }
        else
          return { allowed: true, line_number: 0 }  # Specific agent found but no match
        end
      end

      # If we found specific agent section but no rules matched, allow
      return { allowed: true, line_number: 0 } if @found_specific_agent

      # Fall back to global (*) rules
      if global_allow && global_allow[:priority] > NO_MATCH_PRIORITY ||
         global_disallow && global_disallow[:priority] > NO_MATCH_PRIORITY
        # Longer pattern wins; if equal, allow wins
        if global_disallow && global_disallow[:priority] > (global_allow&.dig(:priority) || NO_MATCH_PRIORITY)
          return { allowed: false, line_number: global_disallow[:line_number] }
        else
          return { allowed: true, line_number: global_allow[:line_number] }
        end
      end

      # No rules found, allow by default (open web philosophy)
      { allowed: true, line_number: 0 }
    end

    # Queries robots.txt for the given user agent.
    #
    # Parses robots.txt once and stores rules for efficient repeated URL checking.
    # Returns a RobotsResult with check(url) method to test specific URLs.
    def query(robots_body, user_agent)
      robots_txt = robots_body || ''
      @user_agent = user_agent
      @robots_txt_lines = split_into_lines(robots_txt)

      # Clear previous rules and state
      @rules.clear
      @found_specific_agent = false

      # Parse once and store all rules
      Robots.parse_robots_txt(robots_txt, self)

      # Remember if we found rules for this specific agent
      @found_specific_agent = @found_matching_agent_section

      RobotsResult.new(matcher: self)
    end

    # Parse handler callbacks
    def handle_robots_start
      # Reset state for new robots.txt file
      @current_block_has_global_agent = false
      @current_block_matches_target_agent = false
      @found_matching_agent_section = false
      @current_block_has_rules = false
    end

    def handle_robots_end
      # Nothing to do
    end

    def handle_user_agent(line_num, user_agent)
      # Start of new user-agent block (rules seen signals end of previous block)
      if @current_block_has_rules
        @current_block_matches_target_agent = false
        @current_block_has_global_agent = false
        @current_block_has_rules = false
      end

      # Check if this is a global (wildcard) user-agent
      # Extension: "* " (wildcard + space) is also treated as global
      if global_user_agent?(user_agent)
        @current_block_has_global_agent = true
      else
        # Check if this user-agent matches our target agent
        check_for_matching_agent(user_agent)
      end
    end

    # Checks if user-agent is the global wildcard ('*' or '* ')
    def global_user_agent?(user_agent)
      return false if user_agent.length < WILDCARD_MIN_LENGTH
      return false unless user_agent[0] == WILDCARD_AGENT

      # Accept '*' alone or '* ' (wildcard followed by whitespace)
      user_agent.length == 1 || user_agent[1].match?(/\s/)
    end

    # Checks if user-agent matches our target agent
    def check_for_matching_agent(user_agent)
      extracted = Utilities.extract_user_agent(user_agent)
      if extracted.casecmp?(@user_agent)
        @found_matching_agent_section = true
        @current_block_matches_target_agent = true
      end
    end

    def handle_allow(line_num, value)
      return unless seen_any_agent?
      mark_rules_section_started

      # Store rule for later matching
      is_global = @current_block_has_global_agent && !@current_block_matches_target_agent
      @rules << Rule.new(
        pattern: value,
        type: :allow,
        is_global: is_global,
        line_number: line_num
      )

      # Optimization: normalize "/index.html" and "/index.htm" to "/"
      handle_index_html_optimization(line_num, value)
    end

    def handle_disallow(line_num, value)
      return unless seen_any_agent?
      mark_rules_section_started

      # RFC 9309: Empty Disallow means "allow all" (equivalent to no rule)
      return if value.empty?

      # Store rule for later matching
      is_global = @current_block_has_global_agent && !@current_block_matches_target_agent
      @rules << Rule.new(
        pattern: value,
        type: :disallow,
        is_global: is_global,
        line_number: line_num
      )
    end

    # Marks that we've transitioned from user-agent declarations to rules
    def mark_rules_section_started
      @current_block_has_rules = true
    end

    # Optimization: "/index.html" paths are normalized to "/" for matching
    # Add normalized pattern "/foo/$" for "/foo/index.html"
    def handle_index_html_optimization(line_num, value)
      last_slash_position = value.rindex('/')
      return unless last_slash_position
      return unless value[last_slash_position..].start_with?(INDEX_HTML_PATTERN)

      # Create pattern matching directory: "/foo/index.html" => "/foo/$"
      directory_length = last_slash_position + 1
      normalized_pattern = value[0...directory_length] + '$'
      handle_allow(line_num, normalized_pattern)
    end

    def handle_sitemap(line_num, value)
      # Sitemap directive - ignored
    end

    def handle_unknown_action(line_num, action, value)
      # Unknown directive - ignore
    end

    def report_line_metadata(line_num, metadata)
      # Line metadata - not used in matching logic
    end

    private

    # Checks if we're in a user-agent block (either global or specific)
    def seen_any_agent?
      @current_block_has_global_agent || @current_block_matches_target_agent
    end

    # Splits robots_txt into lines, handling LF, CR, and CRLF line endings
    def split_into_lines(robots_txt)
      return [] if robots_txt.nil? || robots_txt.empty?
      # Split on any line ending combination
      robots_txt.split(/\r\n|\r|\n/)
    end

    # Gets the text of a specific line number (1-indexed)
    # Returns empty string if line number is 0 or out of range
    def get_line_text(line_number)
      return '' if line_number <= 0 || line_number > @robots_txt_lines.length
      @robots_txt_lines[line_number - 1]
    end
  end
end
