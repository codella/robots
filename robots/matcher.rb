# frozen_string_literal: true

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
  # is the official way of Google crawler to match robots.txt.
  #
  # The entry point for the user is to call one of the *allowed_by_robots?
  # methods that return directly if a URL is being allowed according to the
  # robots.txt and the crawl agent.
  # The RobotsMatcher can be re-used for URLs/robots.txt but is NOT thread-safe.
  class RobotsMatcher < RobotsParseHandler
    # Wildcard user-agent that matches all crawlers
    WILDCARD_AGENT = '*'
    WILDCARD_MIN_LENGTH = 1

    # Google optimization: "/index.html" and "/index.htm" normalize to "/"
    INDEX_HTML_PATTERN = '/index.htm'

    attr_reader :ever_seen_specific_agent

    def initialize
      super
      @allow = MatchHierarchy.new
      @disallow = MatchHierarchy.new

      # Tracks if current user-agent block includes the wildcard (*) agent
      @current_block_has_global_agent = false

      # Tracks if current user-agent block matches our target agents
      @current_block_matches_target_agent = false

      # Tracks if ANY block in the file matched our target agents
      # (important for determining whether to fall back to global rules)
      @found_matching_agent_section = false

      # Tracks if we've seen Allow/Disallow directives after user-agent declarations
      # (signals transition from user-agent declarations to rules)
      @current_block_has_rules = false

      @path = nil
      @user_agents = nil

      @match_strategy = LongestMatchRobotsMatchStrategy.new
    end

    # Returns true iff 'url' is allowed to be fetched by any member of the
    # "user_agents" array. 'url' must be %-encoded according to RFC3986.
    def allowed_by_robots?(robots_body, user_agents, url)
      # The url is not normalized (escaped, percent encoded) here because the user
      # is asked to provide it in escaped form already
      path = Utilities.get_path_params_query(url)
      init_user_agents_and_path(user_agents, path)
      Robots.parse_robots_txt(robots_body, self)
      !disallow?
    end

    # Do robots check for 'url' when there is only one user agent. 'url' must
    # be %-encoded according to RFC3986.
    def one_agent_allowed_by_robots?(robots_txt, user_agent, url)
      allowed_by_robots?(robots_txt, [user_agent], url)
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
      # Google extension: "* " (wildcard + space) is also treated as global
      if global_user_agent?(user_agent)
        @current_block_has_global_agent = true
      else
        # Check if this user-agent matches any of our target agents
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

    # Checks if user-agent matches any of our target agents
    def check_for_matching_agent(user_agent)
      extracted = Utilities.extract_user_agent(user_agent)
      @user_agents.each do |target_agent|
        if extracted.casecmp?(target_agent)
          @found_matching_agent_section = true
          @current_block_matches_target_agent = true
          break
        end
      end
    end

    def handle_allow(line_num, value)
      return unless seen_any_agent?
      mark_rules_section_started

      priority = @match_strategy.match_allow(@path, value)
      update_match_if_higher_priority(@allow, priority, line_num)

      # Google-specific optimization: normalize "/index.html" and "/index.htm" to "/"
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

    # Google optimization: "/index.html" paths are normalized to "/" for matching
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
      # Sitemap directive - we don't process it in matching logic
    end

    def handle_unknown_action(line_num, action, value)
      # Unknown directive - ignore
    end

    private

    def init_user_agents_and_path(user_agents, path)
      @path = path
      # assert(path[0] == '/')
      @user_agents = user_agents
    end

    # Checks if we're in a user-agent block (either global or specific)
    def seen_any_agent?
      @current_block_has_global_agent || @current_block_matches_target_agent
    end
  end
end
