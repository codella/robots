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
    attr_reader :ever_seen_specific_agent

    def initialize
      super
      @allow = MatchHierarchy.new
      @disallow = MatchHierarchy.new

      @seen_global_agent = false
      @seen_specific_agent = false
      @ever_seen_specific_agent = false
      @seen_separator = false

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
    def disallow?
      if @allow.specific.priority > 0 || @disallow.specific.priority > 0
        return @disallow.specific.priority > @allow.specific.priority
      end

      if @ever_seen_specific_agent
        # Matching group for user-agent but either without disallow or empty one,
        # i.e. priority == 0
        return false
      end

      if @disallow.global.priority > 0 || @allow.global.priority > 0
        return @disallow.global.priority > @allow.global.priority
      end

      false
    end

    # Returns true if we are disallowed from crawling a matching URI. Ignores any
    # rules specified for the default user agent, and bases its results only on
    # the specified user agents.
    def disallow_ignore_global?
      if @allow.specific.priority > 0 || @disallow.specific.priority > 0
        return @disallow.specific.priority > @allow.specific.priority
      end
      false
    end

    # Returns the line that matched or 0 if none matched
    def matching_line
      if @ever_seen_specific_agent
        return Match.higher_priority_match(@disallow.specific, @allow.specific).line
      end
      Match.higher_priority_match(@disallow.global, @allow.global).line
    end

    # Verifies that the given user agent is valid to be matched against
    # robots.txt. Valid user agent strings only contain the characters
    # [a-zA-Z_-].
    def self.valid_user_agent_to_obey?(user_agent)
      Utilities.valid_user_agent?(user_agent)
    end

    # Parse handler callbacks
    def handle_robots_start
      # This is a new robots.txt file, so we need to reset all the instance member
      # variables
      @allow.clear
      @disallow.clear

      @seen_global_agent = false
      @seen_specific_agent = false
      @ever_seen_specific_agent = false
      @seen_separator = false
    end

    def handle_robots_end
      # Nothing to do
    end

    def handle_user_agent(line_num, user_agent)
      if @seen_separator
        @seen_specific_agent = @seen_global_agent = @seen_separator = false
      end

      # Google-specific optimization: a '*' followed by space and more characters
      # in a user-agent record is still regarded a global rule
      if user_agent.length >= 1 && user_agent[0] == '*' &&
         (user_agent.length == 1 || user_agent[1].match?(/\s/))
        @seen_global_agent = true
      else
        extracted = Utilities.extract_user_agent(user_agent)
        @user_agents.each do |agent|
          if extracted.casecmp?(agent)
            @ever_seen_specific_agent = @seen_specific_agent = true
            break
          end
        end
      end
    end

    def handle_allow(line_num, value)
      return unless seen_any_agent?
      @seen_separator = true

      priority = @match_strategy.match_allow(@path, value)
      if priority >= 0
        if @seen_specific_agent
          if @allow.specific.priority < priority
            @allow.specific.set(priority, line_num)
          end
        else
          # assert(@seen_global_agent)
          if @allow.global.priority < priority
            @allow.global.set(priority, line_num)
          end
        end
      else
        # Google-specific optimization: 'index.html' is normalized to '/'
        slash_pos = value.rindex('/')
        if slash_pos && value[slash_pos..].start_with?('/index.htm')
          len = slash_pos + 1
          newpattern = value[0...len] + '$'
          handle_allow(line_num, newpattern)
        end
      end
    end

    def handle_disallow(line_num, value)
      return unless seen_any_agent?
      @seen_separator = true

      priority = @match_strategy.match_disallow(@path, value)
      if priority >= 0
        if @seen_specific_agent
          if @disallow.specific.priority < priority
            @disallow.specific.set(priority, line_num)
          end
        else
          # assert(@seen_global_agent)
          if @disallow.global.priority < priority
            @disallow.global.set(priority, line_num)
          end
        end
      end
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

    def seen_any_agent?
      @seen_global_agent || @seen_specific_agent
    end
  end
end
