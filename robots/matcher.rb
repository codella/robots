# frozen_string_literal: true

require 'set'
require_relative 'parser'
require_relative 'match_strategy'
require_relative 'utilities'

module Robots
  # Represents a match with priority and line number
  class Match
    NO_MATCH_PRIORITY = -1

    attr_reader :priority, :line

    def initialize(priority = NO_MATCH_PRIORITY, line = 0)
      @priority = priority
      @line = line
    end

    def set(priority, line)
      @priority = priority
      @line = line
    end

    def clear
      set(NO_MATCH_PRIORITY, 0)
    end

    def self.higher_priority_match(a, b)
      a.priority > b.priority ? a : b
    end
  end

  # Holds global and specific match hierarchies
  class MatchHierarchy
    attr_accessor :global, :specific

    def initialize
      @global = Match.new
      @specific = Match.new
    end

    def clear
      @global.clear
      @specific.clear
    end
  end

  # RobotsMatcher - matches robots.txt against URLs
  #
  # The Matcher uses a default match strategy for Allow/Disallow patterns which
  # is the standard way to match robots.txt.
  #
  # The entry point for the user is to call the *allowed? method that returns
  # directly if a URL is being allowed according to the robots.txt and the crawl agent.
  # The RobotsMatcher can be re-used for URLs/robots.txt but is NOT thread-safe.
  class RobotsMatcher
    # Wildcard user-agent that matches all crawlers
    WILDCARD_AGENT = '*'
    WILDCARD_MIN_LENGTH = 1

    # Optimization: "/index.html" and "/index.htm" normalize to "/"
    INDEX_HTML_PATTERN = '/index.htm'

    attr_reader :ever_seen_specific_agent

    def initialize
      @allow = MatchHierarchy.new
      @disallow = MatchHierarchy.new

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

      @path = nil
      @user_agent = nil

      @match_strategy = LongestMatchRobotsMatchStrategy.new

      # Sitemap URLs (deduplicated)
      @sitemaps = Set.new

      # Crawl-delay values per user-agent scope
      @crawl_delay_specific = nil
      @crawl_delay_global = nil

      # Robots.txt content split into lines for line text retrieval
      @robots_txt_lines = []

      # Stored robots_txt content and user_agent for subsequent URL checks
      @stored_robots_txt = nil
      @stored_user_agent = nil
    end

    # Checks a specific URL against the parsed robots.txt rules
    # Returns UrlCheckResult with allowed status, line number, and line text
    def check_url(url)
      path = Utilities.get_path_params_query(url)

      # Re-initialize for this URL check
      init_user_agent_and_path(@stored_user_agent, path)

      # Reset match state
      @allow.clear
      @disallow.clear
      @sitemaps.clear
      @crawl_delay_specific = nil
      @crawl_delay_global = nil

      # Re-parse robots.txt for this URL
      Robots.parse_robots_txt(@stored_robots_txt, self)

      allowed = !disallow?
      line = matching_line
      line_text = get_line_text(line)

      UrlCheckResult.new(
        allowed: allowed,
        line_number: line,
        line_text: line_text
      )
    end

    # Queries robots.txt for the given user agent.
    #
    # Returns a RobotsResult with:
    # - sitemaps: array of unique sitemap URLs found
    # - crawl_delay: crawl delay for the user agent (nil if not specified)
    # - check(url): method to check if specific URLs are allowed
    def query(robots_body, user_agent)
      # Store for later URL checks
      @stored_robots_txt = robots_body || ''
      @stored_user_agent = user_agent
      @robots_txt_lines = split_into_lines(@stored_robots_txt)

      # Parse robots.txt once to extract sitemaps and crawl-delay
      # Use empty path for initial parse (just to get global info)
      init_user_agent_and_path(user_agent, '/')
      Robots.parse_robots_txt(@stored_robots_txt, self)

      crawl_delay = determine_crawl_delay
      sitemaps_array = @sitemaps.to_a

      RobotsResult.new(
        sitemaps: sitemaps_array,
        crawl_delay: crawl_delay,
        matcher: self
      )
    end

    # Returns true if we are disallowed from crawling a matching URI
    #
    # Priority-based decision logic:
    # 1. Check agent-specific rules first (highest priority)
    # 2. If we found a matching agent section but no rules, allow by default
    # 3. Fall back to global (*) rules
    # 4. If no rules found, allow by default
    #
    # When comparing allow vs disallow:
    # - Longer pattern wins (higher priority)
    # - If equal length, allow wins (disallow.priority must be > allow.priority)
    def disallow?
      # Check agent-specific rules first (highest priority)
      if has_specific_agent_rules?
        return disallow_wins_over_allow?(@disallow.specific, @allow.specific)
      end

      # If we found a specific agent section but no rules matched, allow by default
      return false if @found_matching_agent_section

      # Fall back to global (*) rules
      if has_global_rules?
        return disallow_wins_over_allow?(@disallow.global, @allow.global)
      end

      # No rules found, allow by default (open web philosophy)
      false
    end

    # Checks if either allow or disallow rules matched for the specific agent
    def has_specific_agent_rules?
      rule_matched?(@allow.specific) || rule_matched?(@disallow.specific)
    end

    # Checks if either allow or disallow rules matched for the global agent
    def has_global_rules?
      rule_matched?(@allow.global) || rule_matched?(@disallow.global)
    end

    # Checks if a rule actually matched (priority >= 0 means match)
    def rule_matched?(match)
      match.priority > Match::NO_MATCH_PRIORITY
    end

    # In robots.txt, longest match wins; if equal length, allow wins
    # Therefore disallow only wins if its priority is strictly greater
    def disallow_wins_over_allow?(disallow_match, allow_match)
      disallow_match.priority > allow_match.priority
    end

    # Returns true if we are disallowed from crawling a matching URI. Ignores any
    # rules specified for the default user agent, and bases its results only on
    # the specified user agents.
    def disallow_ignore_global?
      return false unless has_specific_agent_rules?
      disallow_wins_over_allow?(@disallow.specific, @allow.specific)
    end

    # Returns the line number that matched, or 0 if none matched
    # Prefers specific agent rules over global rules
    def matching_line
      if @found_matching_agent_section
        Match.higher_priority_match(@disallow.specific, @allow.specific).line
      else
        Match.higher_priority_match(@disallow.global, @allow.global).line
      end
    end

    # Verifies that the given user agent is valid to be matched against
    # robots.txt. Valid user agent strings only contain the characters
    # [a-zA-Z_-].
    def self.valid_user_agent_to_obey?(user_agent)
      Utilities.valid_user_agent?(user_agent)
    end

    # Parse handler callbacks
    def handle_robots_start
      # Reset state for new robots.txt file
      @allow.clear
      @disallow.clear

      @current_block_has_global_agent = false
      @current_block_matches_target_agent = false
      @found_matching_agent_section = false
      @current_block_has_rules = false

      @sitemaps.clear
      @crawl_delay_specific = nil
      @crawl_delay_global = nil
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

      priority = @match_strategy.match_allow(@path, value)
      update_match_if_higher_priority(@allow, priority, line_num)

      # Optimization: normalize "/index.html" and "/index.htm" to "/"
      handle_index_html_optimization(line_num, value, priority) if priority < 0
    end

    def handle_disallow(line_num, value)
      return unless seen_any_agent?
      mark_rules_section_started

      priority = @match_strategy.match_disallow(@path, value)
      update_match_if_higher_priority(@disallow, priority, line_num)
    end

    # Marks that we've transitioned from user-agent declarations to rules
    def mark_rules_section_started
      @current_block_has_rules = true
    end

    # Updates match if the new priority is higher than current
    # Routes to specific or global match based on current agent block
    def update_match_if_higher_priority(match_hierarchy, priority, line_num)
      return if priority < 0  # No match

      target_match = if @current_block_matches_target_agent
                       match_hierarchy.specific
                     else
                       match_hierarchy.global
                     end

      if target_match.priority < priority
        target_match.set(priority, line_num)
      end
    end

    # Optimization: "/index.html" paths are normalized to "/" for matching
    # If "/foo/index.html" didn't match, try "/foo/$" instead
    def handle_index_html_optimization(line_num, value, priority)
      return unless priority < 0  # Only if original didn't match

      last_slash_position = value.rindex('/')
      return unless last_slash_position
      return unless value[last_slash_position..].start_with?(INDEX_HTML_PATTERN)

      # Create pattern matching directory: "/foo/index.html" => "/foo/$"
      directory_length = last_slash_position + 1
      normalized_pattern = value[0...directory_length] + '$'
      handle_allow(line_num, normalized_pattern)
    end

    def handle_sitemap(line_num, value)
      # Sitemap directive is global (not scoped to user-agent)
      @sitemaps.add(value) unless value.empty?
    end

    def handle_crawl_delay(line_num, value)
      return unless seen_any_agent?

      # Parse crawl-delay value (should be a number, possibly with decimals)
      delay = parse_crawl_delay(value)
      return if delay.nil?

      # Store based on current user-agent scope
      if @current_block_matches_target_agent
        @crawl_delay_specific = delay
      elsif @current_block_has_global_agent
        @crawl_delay_global = delay
      end
    end

    def handle_unknown_action(line_num, action, value)
      # Unknown directive - ignore
    end

    def report_line_metadata(line_num, metadata)
      # Line metadata - not used in matching logic
    end

    private

    def init_user_agent_and_path(user_agent, path)
      @path = path
      # assert(path[0] == '/')
      @user_agent = user_agent
    end

    # Checks if we're in a user-agent block (either global or specific)
    def seen_any_agent?
      @current_block_has_global_agent || @current_block_matches_target_agent
    end

    # Parses crawl-delay value, returns nil if invalid
    # Accepts integers and floats (e.g., "5", "2.5")
    def parse_crawl_delay(value)
      return nil if value.nil? || value.empty?

      # Try to parse as float (handles both integers and decimals)
      delay = Float(value) rescue nil
      return nil if delay.nil? || delay.negative?

      delay
    end

    # Determines which crawl-delay to use based on user-agent matching
    # Priority: specific user-agent > global (*) > nil
    def determine_crawl_delay
      if @found_matching_agent_section && !@crawl_delay_specific.nil?
        @crawl_delay_specific
      elsif !@crawl_delay_global.nil?
        @crawl_delay_global
      else
        nil
      end
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
