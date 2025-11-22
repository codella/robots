# Robots.txt Parsing and Matching Architecture

## Overview

This library implements a **two-phase architecture** optimized for performance:

1. **Phase 1: Parse Once** - Parse robots.txt content and store rules in memory
2. **Phase 2: Check Many** - Efficiently check URLs against stored rules without reparsing

This design achieves ~70,000 URL checks per second by parsing the robots.txt file only once during initialization and reusing the parsed rules for all subsequent URL checks.

## Phase 1: Parsing Process

### High-Level Flow

```
robots.txt → RobotsTxtParser → Callbacks → Robots instance → Stored Rules
```

The parsing process uses a **callback pattern** where the parser invokes handler methods on the `Robots` instance as it discovers directives.

### Step-by-Step Parsing

#### 1. Parser Initialization (`robots/parser.rb:70-72`)

```ruby
parser = RobotsTxtParser.new(robots_body, handler)
parser.parse
```

The parser receives:
- `robots_body`: Raw robots.txt content as a string
- `handler`: The `Robots` instance that implements the `RobotsParseHandler` interface

#### 2. Line Splitting (`robots/parser.rb:74-94`)

The parser processes the file using **Ruby's standard string splitting** to handle:

- **UTF-8 BOM Detection**: Checks first 3 bytes for BOM sequence `[0xEF, 0xBB, 0xBF]` and removes if present
- **Line Ending Normalization**: Handles LF (`\n`), CR (`\r`), and CRLF (`\r\n`) line endings seamlessly
- **Line Length Limits**: Enforces maximum line length of 16,664 bytes (based on IE's historical URL limit × 8)

**Parsing Logic:**
```ruby
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
```

**Line Ending Handling**: The regex `/\r\n|\r|\n/` splits on any line ending format, with the regex engine automatically handling CRLF as a single delimiter (matches `\r\n` before trying `\r` or `\n` separately).

#### 3. Line Parsing (`robots/parser.rb:101-122`)

Each complete line is parsed to extract key-value pairs:

**Standard Format:**
```
Disallow: /admin/
```

**Extension Format** (whitespace separator when colon missing):
```
Disallow /admin/
```

The parser:
1. **Strips comments**: Everything after `#` is removed
2. **Finds separator**: Looks for `:` or falls back to whitespace
3. **Extracts key-value**: Splits on separator and trims whitespace
4. **Validates format**: Rejects lines with invalid structure

Example from `robots/parser.rb:127-136`:
```ruby
def get_key_and_value_from(line, metadata)
  line = strip_comment(line, metadata)
  return [nil, nil] if handle_empty_line(line, metadata)
  separator_position = find_key_value_separator(line, metadata)
  return [nil, nil] unless separator_position
  extract_key_and_value(line, separator_position, metadata)
end
```

#### 4. Directive Recognition (`robots/parser.rb:39-57`)

The `ParsedRobotsKey` class converts directive strings to enumeration values:

| Directive Text | Enumeration | Case Sensitive? |
|---------------|-------------|-----------------|
| `User-agent:` | `:user_agent` | No (case-insensitive) |
| `Allow:` | `:allow` | No |
| `Disallow:` | `:disallow` | No |
| `Sitemap:` | `:sitemap` | No |
| Anything else | `:unknown` | - |

Recognition uses `start_with?` on lowercased keys:
```ruby
key_lower = key&.downcase || ''
@type = if key_lower.start_with?('user-agent')
          USER_AGENT
        elsif key_lower.start_with?('allow')
          ALLOW
        # ...
```

#### 5. Pattern Escaping (`robots/parser.rb:200-210` and `robots/utilities.rb:58-103`)

Before emitting Allow/Disallow directives, the parser normalizes patterns:

**Two transformations:**
1. **Uppercase hex digits**: `%2f` → `%2F`
2. **Percent-encode non-ASCII bytes**: `/José` → `/Jos%C3%A9`

This ensures consistent matching regardless of encoding variations in the robots.txt file.

**User-agent and Sitemap values are NOT escaped** - they're literal strings, not patterns.

#### 6. Callback Emission (`robots/parser.rb:212-227`)

The parser invokes handler methods based on directive type:

```ruby
case key.type
when ParsedRobotsKey::USER_AGENT
  @handler.handle_user_agent(line, value)
when ParsedRobotsKey::ALLOW
  @handler.handle_allow(line, value)
when ParsedRobotsKey::DISALLOW
  @handler.handle_disallow(line, value)
when ParsedRobotsKey::SITEMAP
  @handler.handle_sitemap(line, value)
# ...
end
```

Each callback receives:
- `line`: 1-indexed line number in the robots.txt file
- `value`: The normalized/escaped directive value

### Handler Implementation (Robots Class)

The `Robots` class implements the callback interface and builds the rule database.

#### User-Agent Grouping (`robots.rb:241-257`)

User-agent declarations define **blocks** of rules. The handler tracks:
- `@current_block_has_global_agent`: Is `*` (wildcard) in this block?
- `@current_block_matches_target_agent`: Does this block match our user-agent?
- `@found_matching_agent_section`: Have we seen ANY block for our user-agent?

**Block Transition Logic:**
- A new `User-agent:` directive **after** seeing Allow/Disallow rules starts a new block
- Multiple consecutive `User-agent:` declarations belong to the same block

Example:
```
User-agent: FooBot    # Block 1 starts
User-agent: BarBot    # Still block 1
Disallow: /admin/     # Block 1 rules

User-agent: *         # Block 2 starts (new block because we saw rules)
Allow: /
```

#### User-Agent Matching (`robots.rb:259-275`)

**Global Agent Detection** (`robots.rb:260-266`):
```ruby
def global_user_agent?(user_agent)
  return false if user_agent.length < WILDCARD_MIN_LENGTH
  return false unless user_agent[0] == WILDCARD_AGENT
  # Accept '*' alone or '* ' (wildcard followed by whitespace)
  user_agent.length == 1 || user_agent[1].match?(/\s/)
end
```

**Specific Agent Matching** (`robots.rb:269-275`):
```ruby
def check_for_matching_agent(user_agent)
  extracted = Utilities.extract_user_agent(user_agent)
  if extracted.casecmp?(@user_agent)
    @found_matching_agent_section = true
    @current_block_matches_target_agent = true
  end
end
```

The `extract_user_agent` function extracts the product name:
- Stops at first non-`[a-zA-Z_-]` character
- `"FooBot/2.1"` → `"FooBot"`
- `"Mozilla 5.0"` → `"Mozilla"`
- Comparison is **case-insensitive**

#### Rule Storage (`robots.rb:277-309`)

When Allow/Disallow directives are encountered:

```ruby
def handle_allow(line_num, value)
  return unless seen_any_agent?  # Ignore if no user-agent declared yet
  mark_rules_section_started      # Signal transition to rules section

  # Determine if rule is global or specific
  is_global = @current_block_has_global_agent &&
              !@current_block_matches_target_agent

  # Store rule for later matching
  @rules << Rule.new(
    pattern: value,
    type: :allow,
    is_global: is_global,
    line_number: line_num
  )

  # Optimization: /index.html normalization
  handle_index_html_optimization(line_num, value)
end
```

**Key Decision - Global vs. Specific:**
- **Specific rule**: Current block matches our target user-agent
- **Global rule**: Current block has wildcard `*` but doesn't match our specific agent
- Rules are tagged with `is_global` flag for later priority resolution

**Empty Disallow Handling** (`robots.rb:298-299`):
Per RFC 9309, `Disallow:` (empty value) means "allow all" and is equivalent to no rule, so it's ignored.

#### Index.html Optimization (`robots.rb:316-327`)

When an Allow rule matches `/*/index.html` or `/*/index.htm`, the parser automatically creates an additional rule for the directory path with end-anchor:

```
Allow: /foo/index.html
  ↓ (automatically generates)
Allow: /foo/$
```

This ensures that accessing `/foo/` is treated the same as `/foo/index.html`.

Implementation:
```ruby
def handle_index_html_optimization(line_num, value)
  last_slash_position = value.rindex('/')
  return unless last_slash_position
  return unless value[last_slash_position..].start_with?(INDEX_HTML_PATTERN)

  # Create pattern matching directory: "/foo/index.html" => "/foo/$"
  directory_length = last_slash_position + 1
  normalized_pattern = value[0...directory_length] + '$'
  handle_allow(line_num, normalized_pattern)
end
```

#### Sitemap Handling (`robots.rb:329-332`)

Sitemaps are **always global** per RFC 9309 Section 2.3.5 - they apply regardless of user-agent:

```ruby
def handle_sitemap(line_num, value)
  # RFC 9309: Sitemaps are always global (not user-agent specific)
  @sitemaps << Sitemap.new(url: value, line_number: line_num)
end
```

All sitemap URLs are collected and exposed via the `sitemaps` method.

## Phase 2: URL Matching Process

### High-Level Flow

```
URL → Extract Path → Match Against Rules → Apply Priority → Return Result
```

### Step-by-Step Matching

#### 1. Path Extraction (`robots.rb:149-150` and `robots/utilities.rb:27-52`)

```ruby
def check_url(url)
  path = Utilities.get_path_params_query(url)
  # ...
end
```

The `get_path_params_query` function extracts the path portion from a URL using Ruby's built-in `URI` class:

**Transformations:**
- `http://example.com/page` → `/page`
- `http://example.com/page?query` → `/page?query`
- `http://example.com` → `/`
- `//example.com/path` → `/path` (protocol-relative URLs)
- `/path#fragment` → `/path` (fragments stripped)

**Key behaviors:**
- Always returns a path starting with `/`
- Preserves query strings and parameters
- Removes URL fragments (everything after `#`)
- Handles protocol-relative URLs (`//example.com`)

#### 2. Rule Matching (`robots.rb:153` and `robots.rb:168-225`)

```ruby
best_match = match_path_against_rules(path)
```

The matching algorithm iterates through all stored rules and finds the best matches:

**Tracking Best Matches:**
```ruby
best_allow = { priority: NO_MATCH_PRIORITY, line_number: 0, is_global: false }
best_disallow = { priority: NO_MATCH_PRIORITY, line_number: 0, is_global: false }
```

**For Each Rule:**
```ruby
@rules.each do |rule|
  priority = @match_strategy.match_allow(path, rule.pattern)
  next if priority < 0  # No match

  # Update best match if this is better
  if rule.type == :allow
    if priority > best_allow[:priority] ||
       (priority == best_allow[:priority] && !rule.is_global && best_allow[:is_global])
      best_allow = { priority: priority, line_number: rule.line_number,
                     is_global: rule.is_global }
    end
  else  # :disallow
    # Similar logic for disallow
  end
end
```

**Priority Value** (from `robots/match_strategy.rb:114-117`):
- `-1` (NO_MATCH_PRIORITY): Pattern did not match
- `0` (EMPTY_PATTERN_PRIORITY): Matched empty pattern
- `> 0`: Pattern matched, priority equals pattern length

#### 3. Pattern Matching Algorithm (`robots/match_strategy.rb:39-104`)

The `RobotsMatchStrategy.matches(path, pattern)` method implements pattern matching with:
- **Wildcards (`*`)**: Match zero or more characters
- **End anchors (`$`)**: Match end of path (only when at end of pattern)

**Dynamic Programming Approach:**

The algorithm maintains an array of "matching positions" representing which indices in the path can match the current prefix of the pattern.

```ruby
# Initially, only position 0 (start of path) matches
matching_positions = Array.new(path_length + 1, 0)
matching_positions[0] = 0
match_count = 1

pattern.each_char.with_index do |pattern_char, pattern_index|
  if at_end_anchor?(pattern_char, pattern_index, pattern)
    # END_ANCHOR at end: path must also end here
    return last_match_at_end_of_path?(matching_positions, match_count, path_length)
  elsif pattern_char == WILDCARD
    # Wildcard: expand to match all remaining positions
    match_count = handle_wildcard(matching_positions, match_count, path_length)
  else
    # Literal char: filter to positions where path matches
    match_count = handle_literal_char(matching_positions, match_count, path,
                                      pattern_char, path_length)
    return false if match_count == 0
  end
end
```

**Wildcard Handling** (`robots/match_strategy.rb:83-89`):
```ruby
# From the first matching position, we can now match at
# every subsequent position in the path
def self.handle_wildcard(matching_positions, match_count, path_length)
  new_match_count = path_length - matching_positions[0] + 1
  (1...new_match_count).each do |index|
    matching_positions[index] = matching_positions[index - 1] + 1
  end
  new_match_count
end
```

**Literal Character Handling** (`robots/match_strategy.rb:94-104`):
```ruby
# Filter matching positions to only those where path has this character
def self.handle_literal_char(matching_positions, match_count, path,
                             pattern_char, path_length)
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
```

**Complexity:**
- **Time**: O(path_length × pattern_length)
- **Space**: O(path_length)

This avoids exponential worst-case performance when matching complex patterns with many wildcards.

**Pattern Matching Examples:**

| Path | Pattern | Matches? | Explanation |
|------|---------|----------|-------------|
| `/admin/` | `/admin` | ✅ Yes | Pattern is prefix of path |
| `/admin/` | `/admin/$` | ❌ No | `$` requires exact end, path is longer |
| `/admin` | `/admin/$` | ✅ Yes | `$` matches path end exactly |
| `/page.html` | `/*.html` | ✅ Yes | `*` matches `page` |
| `/admin/secret.html` | `/admin/*.html` | ✅ Yes | `*` matches `secret` |
| `/page.php` | `/*.html` | ❌ No | Literal `.html` doesn't match `.php` |

#### 4. Priority Resolution (`robots.rb:190-224`)

After finding best Allow and Disallow matches, apply RFC 9309 priority rules:

**Priority Hierarchy:**

1. **Specific agent rules** (highest priority)
   - Rules from blocks matching our user-agent
   - If specific agent found but no rules matched: **allow by default**

2. **Global (`*`) rules**
   - Rules from wildcard user-agent blocks
   - Only checked if no specific agent section exists

3. **No rules**: **Allow by default** (open web philosophy)

**Tie-Breaking Rules:**

When multiple rules match the same path:

1. **Longest pattern wins**: Priority is based on pattern length
2. **Equal length**: Allow wins over Disallow
3. **Equal priority**: Specific beats global

**Implementation:**

```ruby
# Separate specific and global rules
specific_allow = best_allow[:is_global] ? nil : best_allow
specific_disallow = best_disallow[:is_global] ? nil : best_disallow
global_allow = best_allow[:is_global] ? best_allow : nil
global_disallow = best_disallow[:is_global] ? best_disallow : nil

# Check agent-specific rules first
if specific_allow && specific_allow[:priority] > NO_MATCH_PRIORITY ||
   specific_disallow && specific_disallow[:priority] > NO_MATCH_PRIORITY
  # Longer pattern wins; if equal, allow wins
  if specific_disallow &&
     specific_disallow[:priority] > (specific_allow&.dig(:priority) || NO_MATCH_PRIORITY)
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
# ... similar logic for global rules ...

# No rules found, allow by default
{ allowed: true, line_number: 0 }
```

#### 5. Result Construction (`robots.rb:155-164`)

```ruby
allowed = best_match[:allowed]
line = best_match[:line_number]
line_text = get_line_text(line)

UrlCheckResult.new(
  allowed: allowed,
  line_number: line,
  line_text: line_text
)
```

The result includes:
- `allowed?`: Boolean indicating if URL is allowed
- `line_number`: Line number of the matching rule (0 if no match)
- `line_text`: Full text of the matching line (empty if no match)

## Priority Examples

### Example 1: Longest Match Wins

```
User-agent: *
Disallow: /admin
Allow: /admin/public
```

Checking `/admin/public/page.html`:
- `Disallow: /admin` matches with priority 6 (pattern length)
- `Allow: /admin/public` matches with priority 13 (pattern length)
- **Result**: Allowed (longer pattern wins)

### Example 2: Equal Length - Allow Wins

```
User-agent: *
Disallow: /page.html
Allow: /page.html
```

Checking `/page.html`:
- Both patterns have priority 10
- **Result**: Allowed (Allow wins on tie)

### Example 3: Specific Agent vs Global

```
User-agent: MyBot
Disallow: /private

User-agent: *
Allow: /
```

Checking `/private/data.html` as `MyBot`:
- Specific rule `Disallow: /private` matches with priority 8
- Global rule `Allow: /` matches with priority 1
- **Result**: Disallowed (specific agent rules have higher priority than global)

### Example 4: Specific Agent Found, No Match

```
User-agent: MyBot
Disallow: /admin

User-agent: *
Disallow: /
```

Checking `/public/page.html` as `MyBot`:
- Specific section for `MyBot` exists
- No specific rules match `/public/`
- **Result**: Allowed (specific agent found but no match = allow by default)
- Global rules are **not consulted** because specific agent section exists

### Example 5: Wildcard and End Anchor

```
User-agent: *
Disallow: /*.pdf$
```

Checking paths:
- `/document.pdf` → Disallowed (matches pattern exactly)
- `/document.pdf?download=1` → Allowed (`$` requires end, query prevents match)
- `/files/report.pdf` → Disallowed (`*` matches `files/report`)
- `/pdfs/file.txt` → Allowed (`.pdf$` doesn't match `.txt`)

## Performance Characteristics

### Parse Once, Check Many

The two-phase architecture provides excellent performance:

**Initialization (Parse Once):**
- Parse entire robots.txt: ~O(file_size)
- Store rules in memory: ~O(num_rules)
- One-time cost, typically < 1ms for typical files

**URL Checking (Check Many):**
- Extract path from URL: O(url_length)
- Match against rules: O(num_rules × path_length × avg_pattern_length)
- Typical performance: ~70,000 checks/second

**Memory Usage:**
- Each rule stored as lightweight `Rule` object
- Typical robots.txt: 10-100 rules ≈ 1-10 KB memory

### Optimization Techniques

1. **Pre-parsed Rules**: Rules stored as objects, not reparsed per check
2. **Dynamic Programming**: Pattern matching avoids exponential worst-case
3. **Early Termination**: Matching stops at first mismatch in literal characters
4. **Idiomatic Ruby**: Parser uses standard string methods for simplicity and performance

## Special Features

### UTF-8 and Encoding

**UTF-8 BOM Handling** (`robots/parser.rb:77-82`):
- Detects and removes 3-byte BOM sequence `[0xEF, 0xBB, 0xBF]` at file start
- Uses byte-level comparison to avoid encoding compatibility issues
- Allows robots.txt files saved with BOM to parse correctly

**Non-ASCII Character Normalization** (`robots/utilities.rb:67-103`):
- Non-ASCII bytes in patterns are percent-encoded
- `/José` → `/Jos%C3%A9` (UTF-8 bytes encoded)
- Ensures consistent matching regardless of source encoding

**Percent-Encoding Normalization**:
- Existing percent-escapes uppercased: `%2f` → `%2F`
- Provides canonical representation for matching

### Line Ending Flexibility

The parser handles all common line ending formats:
- **LF** (`\n`): Unix/Linux/macOS
- **CRLF** (`\r\n`): Windows
- **CR** (`\r`): Old macOS
- **Mixed**: Different line endings in same file

This ensures robots.txt files from any platform parse correctly.

### Thread Safety

**NOT Thread-Safe:**
- `Robots` instances are mutable and not synchronized
- `UrlCheckResult` objects should not be shared across threads

**Recommended Pattern:**
```ruby
# Create separate instance per thread
Thread.new do
  robots = Robots.new(robots_txt, 'MyBot')
  result = robots.check(url)
  # Use result in this thread only
end
```

Alternatively, protect shared instance with mutex:
```ruby
robots = Robots.new(robots_txt, 'MyBot')
mutex = Mutex.new

# In threads:
result = mutex.synchronize { robots.check(url) }
```

## Summary

The parsing and matching processes work together to provide:

✅ **Efficient**: Parse once, check many times
✅ **Compliant**: Follows RFC 9309 priority rules
✅ **Robust**: Handles encoding, line endings, and edge cases
✅ **Fast**: ~70,000 URL checks per second
✅ **Simple**: Clean API with detailed result metadata

The two-phase architecture separates expensive parsing from lightweight matching, making this library ideal for applications that need to check many URLs against the same robots.txt file.
