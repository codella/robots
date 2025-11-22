# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Ruby library for parsing and matching robots.txt files according to the Robots Exclusion Protocol (RFC 9309). This is a pure Ruby implementation with no external dependencies.

Supports Allow/Disallow rules with wildcard (`*`) and end-anchor (`$`) patterns.

**Thread-safety**: `Robots` instances are NOT thread-safe. Create separate instances for each thread. The returned `UrlCheckResult` objects should also not be shared across threads.

## Documentation Maintenance

**CRITICAL**: After ANY code change, you MUST review and update:

1. **examples.rb** - Ensure all examples remain accurate and functional
2. **Documentation files** - Update CLAUDE.md, intro.md, and any other docs
3. **Code comments** - Verify all comments reflect current implementation
4. **CLAUDE.md itself** - Update this file if architecture or patterns change

Run `ruby examples.rb` and `ruby robots_test.rb` to verify everything still works after documentation updates.

## Commands

### Running Tests

```bash
ruby robots_test.rb
```

This runs the complete test suite using Minitest. The test file includes a workaround for gem conflicts with railties (lines 5-12) that allows running tests directly without bundler configuration.

### Running Examples

```bash
ruby examples.rb
```

This runs comprehensive usage examples demonstrating the library's features.

### Running Benchmarks

```bash
ruby benchmark.rb
```

This runs a performance benchmark demonstrating the parse-once optimization. Tests 6,000 URL checks to show throughput (~70,000 checks/second).

## Example Usage

**CRITICAL**: The `examples.rb` file demonstrates the library's public API and MUST be kept synchronized with any changes to:
- Public API methods in `robots.rb`
- Method signatures or parameter changes
- Behavior changes that affect usage patterns
- New features added to the library

The example file (`examples.rb`) demonstrates:
1. **Basic usage**: Creating `Robots` instances and using `check(url)` method
2. **User-agent specific rules**: Different rules for different crawlers
3. **Wildcard pattern matching**: Using `*` wildcards and `$` end anchors
4. **Priority rules**: Demonstrating longest-match-wins behavior
5. **Default behavior**: Empty files and missing rules (open web philosophy)
6. **Index.html normalization**: Automatic normalization of `/index.html` and `/index.htm` to `/`
7. **File I/O**: Reading robots.txt from files
8. **Sitemap discovery**: Accessing sitemap URLs (global scope per RFC 9309)

**API Usage**:
```ruby
# Create instance (parses robots.txt for specified user-agent)
robots = Robots.new(robots_txt, 'MyBot')

# Check individual URLs
result = robots.check('http://example.com/page.html')
puts result.allowed?       # => true/false
puts result.line_number   # => line number that matched (0 if no match)
puts result.line_text     # => text of matching line (empty if no match)

# Access sitemaps (always global, not user-agent specific)
robots.sitemaps.each do |sitemap|
  puts "#{sitemap.url} (line #{sitemap.line_number})"
end
```

**When modifying the library**: After any API changes, review and update `examples.rb` to ensure all examples remain accurate and functional. Run the example file to verify it executes without errors.

## Architecture

### Class Structure

The library is organized under the `Robots` class with an instance-based API:

**Public API:**
- `Robots.new(robots_txt, user_agent)` - Parses robots.txt ONCE and stores rules for the specified user-agent (parse-once optimization)
- `robots.check(url)` - Lightweight check against stored rules, returns `UrlCheckResult` with `allowed?`, `line_number`, and `line_text` attributes
- `robots.sitemaps` - Returns array of `Sitemap` objects with `url` and `line_number` (always global, not user-agent specific per RFC 9309)

**Performance Characteristics:**
- **Parse once, check many**: robots.txt is parsed only during initialization
- **Efficient URL checking**: Each `check(url)` call iterates through stored rules without reparsing
- **Throughput**: ~70,000 checks/second on typical robots.txt files
- **Memory**: Stores parsed rules as lightweight `Rule` objects

**Internal Components:**

The main `Robots` class (`robots.rb`) contains the core matching logic:
- `Robots::Rule`: Struct storing individual parsed rules (pattern, type, scope, line number) with automatic equality/hash
- `Robots::Sitemap`: Struct storing sitemap URLs with line numbers (always global per RFC 9309) with automatic equality/hash
- `Robots::UrlCheckResult`: Struct storing check results (allowed, line_number, line_text) with predicate method `allowed?`
- `check_url(url)`: Lightweight method that matches against stored rules without reparsing
- `match_path_against_rules(path)`: Applies RFC priority rules to find best match
- `current_rule_is_global?`: Helper method determining if current rule block is global (DRY principle)
- Implements RFC priority rules: specific agent rules override global rules, longest pattern wins, equal-length patterns favor Allow over Disallow
- Optimizes `/index.html` and `/index.htm` to normalize to `/` for directory matching
- Implements `RobotsParseHandler` interface to receive parsing callbacks
- Uses frozen arrays for sitemaps to prevent external modification

The library has three supporting components:

1. **Utilities** (`robots/utilities.rb`): URL parsing and normalization (idiomatic Ruby)
   - `get_path_params_query(url)`: Extracts path/query from URLs using Ruby's `URI` class with case/when pattern matching
   - `maybe_escape_pattern(src)`: Percent-encodes non-ASCII bytes and normalizes hex digits
   - `extract_user_agent(user_agent)`: Extracts valid user-agent product names using regex one-liner
   - `valid_user_agent?(user_agent)`: Validates user-agent strings using positive regex (no double negatives)
   - `hex_digit?(char)`: Uses idiomatic regex matching instead of range checks

2. **Parser** (`robots/parser.rb`): Robots.txt parsing (idiomatic Ruby)
   - `RobotsTxtParser`: Parses robots.txt content using Ruby's standard string splitting
   - `ParsedRobotsKey`: Directive type enumeration using hash-based lookup (DIRECTIVE_MAP) instead of cascading if/elsif
   - `LineMetadata`: Tracks line characteristics for error reporting
   - Handles UTF-8 BOM with byte-level comparison, multiple line ending formats (LF, CR, CRLF), and line length limits
   - Uses callback pattern via `RobotsParseHandler` interface
   - Simplified boolean logic and one-liner conditionals

3. **Match Strategy** (`robots/match_strategy.rb`): Pattern matching algorithms
   - `RobotsMatchStrategy`: Implements longest-match priority strategy
   - Supports wildcards (`*`) and end anchors (`$`)
   - Uses dynamic programming to avoid worst-case performance: O(path_length * pattern_length) time, O(path_length) space

### Matching Algorithm Flow

The library uses a two-phase approach for optimal performance:

**Phase 1: Initialization (Parse Once)**
1. **Parse**: `RobotsTxtParser` tokenizes robots.txt content by splitting into lines
2. **Callback**: Parser invokes `RobotsParseHandler` methods on the `Robots` instance (`handle_user_agent`, `handle_allow`, `handle_disallow`)
3. **Store**: Handler methods create and store `Robots::Rule` objects with pattern, type (:allow/:disallow), scope (global/specific), and line number
4. **Complete**: All rules are stored in `@rules` array for repeated use

**Phase 2: URL Checking (Check Many)**
1. **Extract path**: Extract path from URL using `Utilities.get_path_params_query(url)`
2. **Match rules**: Iterate through stored `@rules` to find best matching allow/disallow patterns
3. **Apply priority**: Use RFC 9309 priority rules (specific > global, longest match wins, allow wins on tie)
4. **Return result**: Create `UrlCheckResult` with allowed status, line number, and line text

This architecture ensures robots.txt is parsed only once, making repeated URL checks very efficient.

### Matching Rules

**Priority Resolution** (in order):
1. Specific user-agent rules (highest priority)
2. If specific agent found but no rules matched: allow by default
3. Global (`*`) user-agent rules
4. No rules: allow by default (open web philosophy)

**Tie-breaking**:
- Longer pattern wins (higher priority)
- Equal length: Allow wins over Disallow

### Key Implementation Details

- **Case sensitivity**: Directives and user-agents are case-insensitive; paths are case-sensitive
- **Pattern matching**: Uses `matches(path, pattern)` with dynamic programming to handle wildcards efficiently
- **Priority system**: Pattern length determines priority; `NO_MATCH_PRIORITY = -1`, `EMPTY_PATTERN_PRIORITY = 0`
- **User-agent extraction**: Stops at first invalid character (space, slash, special chars), e.g., "FooBot/2.1" becomes "FooBot"
- **User-agent matching**: Case-insensitive, extracts product name only (stops at first space or special char)
- **Path matching**: Case-sensitive
- **UTF-8 handling**: Non-ASCII characters in patterns are percent-encoded (`/foo/ツ` → `/foo/%E3%83%84`)
- **URL normalization**: Always returns paths starting with `/`, strips fragments, handles protocol-relative URLs
- **Percent-encoding**: Normalizes existing percent-escapes to uppercase and encodes non-ASCII bytes
- **Index.html normalization**: `/index.html` and `/index.htm` are treated as equivalent to directory path `/`
- **Line length limit**: 2083 × 8 = 16,664 bytes (based on historical IE URL length limits)

## Code Quality and Ruby Idioms

This library follows Ruby best practices and idiomatic patterns:

### Data Structures
- **Structs over classes**: Simple data containers (Rule, Sitemap, UrlCheckResult) use `Struct.new` for automatic equality, hash, and comparison methods
- **Frozen arrays**: Public collections (sitemaps) are frozen to prevent external modification
- **Keyword arguments**: All Structs use `keyword_init: true` for clarity

### Control Flow
- **Hash-based dispatch**: Directive parsing uses `DIRECTIVE_MAP` instead of cascading if/elsif for maintainability
- **Case/when statements**: URL parsing uses case/when/then for clarity over nested ternaries
- **Modifier if/unless**: Simple conditionals use trailing modifiers (`x = y unless condition`)
- **Combined guard clauses**: Early returns are combined when checking multiple conditions

### Methods
- **Predicate methods**: Boolean methods end with `?` (e.g., `user_agent_allowed?`, `current_rule_is_global?`)
- **DRY principle**: Extracted helper methods like `current_rule_is_global?` eliminate duplication
- **Single responsibility**: Methods focus on one task with clear names

### Pattern Matching
- **Regex over manual**: User-agent extraction uses `user_agent[/^[a-zA-Z_-]*/]` instead of manual string indexing
- **Positive logic**: Validation uses positive regex (`match?(/^[a-zA-Z_-]+$/)`) instead of double negatives

### Performance
- **Frozen constants**: `DIRECTIVE_MAP.freeze` prevents modification and signals immutability
- **Efficient checks**: One-line array inclusion (`![...].include?`) instead of multi-branch case statements

## Testing Strategy

The test suite (`robots_test.rb`) covers:
- Basic scenarios (empty files, empty user-agents, empty URLs)
- Line syntax validation (standard colon separator, whitespace extension)
- User-agent grouping and precedence rules
- Case insensitivity for directives and user-agents
- Path case sensitivity
- Longest-match strategy with equal-length tie-breaking
- UTF-8 and percent-encoding handling
- Special characters (wildcards, end anchors)
- Index.html normalization
- Line ending formats (LF, CR, CRLF, mixed)
- UTF-8 BOM handling
- URL parsing edge cases
- Sitemap exposure with metadata (url, line_number)
- Sitemap global scope (not user-agent specific)
- Empty/duplicate sitemap handling

**Test helper**: Uses `user_agent_allowed?` following Ruby's predicate method naming convention
