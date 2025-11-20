# frozen_string_literal: true

class Robots
  # A RobotsMatchStrategy defines a strategy for matching individual lines in a
  # robots.txt file. Each Match* method should return a match priority, which is
  # interpreted as:
  #
  # match priority < 0:
  #    No match.
  #
  # match priority == 0:
  #    Match, but treat it as if matched an empty pattern.
  #
  # match priority > 0:
  #    Match with priority equal to pattern length.
  class RobotsMatchStrategy
    # Special characters in robots.txt patterns
    WILDCARD = '*'      # Matches zero or more characters
    END_ANCHOR = '$'    # Matches end of path (only when at end of pattern)

    # Match priority constants
    NO_MATCH_PRIORITY = -1      # Pattern did not match
    EMPTY_PATTERN_PRIORITY = 0  # Matched empty pattern
    # Returns true if URI path matches the specified pattern. Pattern is anchored
    # at the beginning of path. END_ANCHOR is special only at the end of pattern.
    #
    # Uses a dynamic programming algorithm to avoid worst-case performance issues
    # when matching patterns with many wildcards against long paths.
    #
    # Algorithm explanation:
    # - Maintains an array of valid matching positions in the path
    # - For each pattern character, updates which path positions can still match
    # - WILDCARD expands to match all remaining positions
    # - Literal characters filter to only matching positions
    # - If no valid positions remain, the match fails
    #
    # Time complexity: O(path_length * pattern_length) worst case
    # Space complexity: O(path_length)
    def self.matches(path, pattern)
      return true if pattern.empty?
      return false if path.nil?

      path = path.to_s
      pattern = pattern.to_s
      path_length = path.length

      # matching_positions tracks which indices in 'path' can match the current
      # prefix of 'pattern'. Initially, only position 0 (start of path) matches.
      matching_positions = Array.new(path_length + 1, 0)
      matching_positions[0] = 0
      match_count = 1

      pattern.each_char.with_index do |pattern_char, pattern_index|
        # Handle end anchor: END_ANCHOR at end of pattern means path must also end
        if at_end_anchor?(pattern_char, pattern_index, pattern)
          return last_match_at_end_of_path?(matching_positions, match_count, path_length)
        end

        if pattern_char == WILDCARD
          match_count = handle_wildcard(matching_positions, match_count, path_length)
        else
          match_count = handle_literal_char(matching_positions, match_count, path, pattern_char, path_length)
          return false if match_count == 0
        end
      end

      true
    end

    # Checks if we're at an end anchor (END_ANCHOR at end of pattern)
    def self.at_end_anchor?(pattern_char, pattern_index, pattern)
      pattern_char == END_ANCHOR && pattern_index == pattern.length - 1
    end

    # Checks if the last matching position is at the end of the path
    def self.last_match_at_end_of_path?(matching_positions, match_count, path_length)
      matching_positions[match_count - 1] == path_length
    end

    # Handles WILDCARD by expanding matching positions to include all remaining path positions
    # WILDCARD matches zero or more characters, so from the first matching position,
    # we can now match at every subsequent position in the path.
    def self.handle_wildcard(matching_positions, match_count, path_length)
      new_match_count = path_length - matching_positions[0] + 1
      (1...new_match_count).each do |index|
        matching_positions[index] = matching_positions[index - 1] + 1
      end
      new_match_count
    end

    # Handles a literal character by filtering matching positions to only those
    # where the path has this character at the current position.
    # This includes END_ANCHOR when it's not at the end of pattern (treated as literal).
    def self.handle_literal_char(matching_positions, match_count, path, pattern_char, path_length)
      new_match_count = 0
      (0...match_count).each do |index|
        position = matching_positions[index]
        if position < path_length && path[position] == pattern_char
          matching_positions[new_match_count] = position + 1
          new_match_count += 1
        end
      end
      new_match_count
    end

    def match_allow(path, pattern)
      matches_pattern(path, pattern)
    end

    private

    # Returns match priority: pattern length if matched, or NO_MATCH_PRIORITY if not
    # Empty patterns return EMPTY_PATTERN_PRIORITY (0)
    def matches_pattern(path, pattern)
      return EMPTY_PATTERN_PRIORITY if pattern.empty?
      self.class.matches(path, pattern) ? pattern.length : NO_MATCH_PRIORITY
    end
  end

  # Longest-match strategy: returns pattern length as priority
  class LongestMatchRobotsMatchStrategy < RobotsMatchStrategy
    # Returns match priority based on pattern length
    # -1 for no match, 0 for empty pattern, length for match
    def match_allow(path, pattern)
      matches_pattern(path, pattern)
    end
  end
end
