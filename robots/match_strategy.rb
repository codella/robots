# frozen_string_literal: true

module Robots
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
    # Returns true if URI path matches the specified pattern. Pattern is anchored
    # at the beginning of path. '$' is special only at the end of pattern.
    #
    # Since 'path' and 'pattern' are both externally determined (by the webmaster),
    # we make sure to have acceptable worst-case performance.
    def self.matches(path, pattern)
      return true if pattern.empty?
      return false if path.nil?

      path = path.to_s
      pattern = pattern.to_s

      pathlen = path.length
      # The pos array holds a sorted list of indexes of 'path', with length
      # 'numpos'.  At the start and end of each iteration of the main loop below,
      # the pos array will hold a list of the prefixes of the 'path' which can
      # match the current prefix of 'pattern'. If this list is ever empty,
      # return false. If we reach the end of 'pattern' with at least one element
      # in pos, return true.

      pos = Array.new(pathlen + 1, 0)
      pos[0] = 0
      numpos = 1

      pattern.each_char.with_index do |pat_char, pat_idx|
        # '$' at end of pattern means match end of path
        if pat_char == '$' && pat_idx == pattern.length - 1
          return pos[numpos - 1] == pathlen
        end

        if pat_char == '*'
          # '*' matches any number of characters
          # Expand pos to include all positions from current to end
          numpos = pathlen - pos[0] + 1
          (1...numpos).each do |i|
            pos[i] = pos[i - 1] + 1
          end
        else
          # Includes '$' when not at end of pattern (treated as literal)
          newnumpos = 0
          (0...numpos).each do |i|
            if pos[i] < pathlen && path[pos[i]] == pat_char
              pos[newnumpos] = pos[i] + 1
              newnumpos += 1
            end
          end
          numpos = newnumpos
          return false if numpos == 0
        end
      end

      true
    end

    def match_allow(path, pattern)
      matches_pattern(path, pattern)
    end

    def match_disallow(path, pattern)
      matches_pattern(path, pattern)
    end

    private

    def matches_pattern(path, pattern)
      return 0 if pattern.empty?
      self.class.matches(path, pattern) ? pattern.length : -1
    end
  end

  # Longest-match strategy: returns pattern length as priority
  class LongestMatchRobotsMatchStrategy < RobotsMatchStrategy
    # Returns match priority based on pattern length
    # -1 for no match, 0 for empty pattern, length for match
    def match_allow(path, pattern)
      matches_pattern(path, pattern)
    end

    def match_disallow(path, pattern)
      matches_pattern(path, pattern)
    end
  end
end
