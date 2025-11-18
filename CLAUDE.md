# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Ruby library for parsing and matching robots.txt files according to the Robots Exclusion Protocol (RFC 9309). This is a pure Ruby implementation with no external dependencies.

## Running Tests

Run all tests:
```bash
ruby robots_test.rb
```

Or using Ruby's built-in test runner:
```bash
ruby -I lib:test test/robots_test.rb
```

The test file includes a Minitest plugin workaround to avoid gem conflicts with railties.

## Architecture

This library uses a **streaming parser with callback-based architecture**:

1. **Entry Point** (`robots.rb`): Main module that loads all components and provides the public API
   - Primary interface: `Robots::RobotsMatcher#allowed?(robots_txt, user_agent, url)`
   - Returns boolean indicating if URL is allowed for given user agent

2. **Parser** (`robots/parser.rb`): Byte-level streaming parser
   - `RobotsTxtParser`: Parses robots.txt line-by-line, handling UTF-8 BOM, multiple line endings (LF/CR/CRLF)
   - `ParsedRobotsKey`: Enumerates directive types (user-agent, allow, disallow, sitemap)
   - Callbacks: Uses handler pattern to emit parsed directives

3. **Matcher** (`robots/matcher.rb`): Core matching logic implementing parse handler callbacks
   - `RobotsMatcher`: Receives parser callbacks and applies matching rules
   - **NOT thread-safe** - create separate instances for concurrent use
   - Maintains separate match hierarchies for global (`*`) and specific user agents
   - Tracks line numbers for debugging purposes

4. **Match Strategy** (`robots/match_strategy.rb`): Pattern matching algorithm
   - `LongestMatchRobotsMatchStrategy`: Default strategy using longest-match-wins rule
   - Dynamic programming algorithm for wildcard (`*`) and end-anchor (`$`) matching
   - Returns priority based on pattern length (longer patterns have higher priority)

5. **Utilities** (`robots/utilities.rb`): Helper functions
   - URL parsing: `get_path_params_query(url)` extracts path/query from URL
   - Percent-encoding normalization: `maybe_escape_pattern(pattern)`
   - User-agent validation and extraction (only `[a-zA-Z_-]` allowed)

## Matching Rules

**Priority Resolution** (in order):
1. Specific user-agent rules (highest priority)
2. If specific agent found but no rules matched: allow by default
3. Global (`*`) user-agent rules
4. No rules: allow by default (open web philosophy)

**Tie-breaking**:
- Longer pattern wins (higher priority)
- Equal length: Allow wins over Disallow

## Key Implementation Details

- **User-agent matching**: Case-insensitive, extracts product name only (stops at first space or special char)
- **Path matching**: Case-sensitive
- **UTF-8 handling**: Non-ASCII characters in patterns are percent-encoded (`/foo/ツ` → `/foo/%E3%83%84`)
- **Index.html normalization**: `/index.html` and `/index.htm` are treated as equivalent to directory path `/`
- **Line length limit**: 2083 × 8 = 16,664 bytes (based on historical IE URL length limits)
