#!/usr/bin/env ruby
# frozen_string_literal: true

# Example demonstrating how to use UrlCheckResult to get detailed information
# about why a URL was allowed or disallowed by robots.txt

require_relative 'robots'

# Sample robots.txt content
robots_txt = <<~ROBOTS
  User-agent: *
  Disallow: /admin/
  Disallow: /private/*.secret$
  Allow: /public/
  Allow: /admin/public/
  Disallow: /temp/
ROBOTS

puts "=" * 80
puts "UrlCheckResult Example - Detailed URL Checking"
puts "=" * 80
puts

# Query robots.txt for a specific user-agent
result = Robots.query(robots_txt, 'MyBot')

puts "Testing various URLs against robots.txt rules:\n\n"

# Example 1: Basic usage - checking a public URL
puts "1. Checking a public URL:"
puts "-" * 40
check = result.check('http://example.com/public/page.html')
puts "URL: http://example.com/public/page.html"
puts "Allowed: #{check.allowed}"
puts "Line number: #{check.line_number}"
puts "Matching line: #{check.line_text.inspect}"
puts

# Example 2: Checking a disallowed admin URL
puts "2. Checking an admin URL:"
puts "-" * 40
check = result.check('http://example.com/admin/secret.html')
puts "URL: http://example.com/admin/secret.html"
puts "Allowed: #{check.allowed}"
puts "Line number: #{check.line_number}"
puts "Matching line: #{check.line_text.inspect}"
puts

# Example 3: Checking an allowed admin/public URL (more specific rule wins)
puts "3. Checking admin/public (longest match wins):"
puts "-" * 40
check = result.check('http://example.com/admin/public/info.html')
puts "URL: http://example.com/admin/public/info.html"
puts "Allowed: #{check.allowed}"
puts "Line number: #{check.line_number}"
puts "Matching line: #{check.line_text.inspect}"
puts "Note: '/admin/public/' (Allow) is longer than '/admin/' (Disallow)"
puts

# Example 4: Checking with wildcard and end anchor
puts "4. Checking URL with pattern matching:"
puts "-" * 40
check = result.check('http://example.com/private/data.secret')
puts "URL: http://example.com/private/data.secret"
puts "Allowed: #{check.allowed}"
puts "Line number: #{check.line_number}"
puts "Matching line: #{check.line_text.inspect}"
puts "Note: Matches pattern '/private/*.secret$' (ends with .secret)"
puts

# Example 5: URL that doesn't match the end anchor
puts "5. Checking URL that doesn't match end anchor:"
puts "-" * 40
check = result.check('http://example.com/private/data.secret.backup')
puts "URL: http://example.com/private/data.secret.backup"
puts "Allowed: #{check.allowed}"
puts "Line number: #{check.line_number}"
puts "Matching line: #{check.line_text.inspect}"
puts "Note: Doesn't match '/private/*.secret$' because it doesn't end with .secret"
puts

# Example 6: URL with no matching rule (default allow)
puts "6. Checking URL with no matching rule:"
puts "-" * 40
check = result.check('http://example.com/blog/post.html')
puts "URL: http://example.com/blog/post.html"
puts "Allowed: #{check.allowed}"
puts "Line number: #{check.line_number}"
puts "Matching line: #{check.line_text.inspect}"
puts "Note: No rule matched, default is to allow (open web philosophy)"
puts

# Example 7: Practical debugging scenario
puts "7. Debugging scenario - batch checking multiple URLs:"
puts "-" * 40
urls = [
  'http://example.com/',
  'http://example.com/admin/',
  'http://example.com/temp/cache.html',
  'http://example.com/public/sitemap.xml'
]

urls.each do |url|
  check = result.check(url)
  status = check.allowed ? "✓ ALLOWED" : "✗ BLOCKED"
  line_info = check.line_number > 0 ? " (line #{check.line_number})" : " (no match)"
  puts "#{status}#{line_info}: #{url}"
end
puts

# Example 8: Using UrlCheckResult attributes for logging
puts "8. Using UrlCheckResult for logging/auditing:"
puts "-" * 40
check = result.check('http://example.com/admin/config')
puts "Creating audit log entry..."
log_entry = {
  timestamp: Time.now.iso8601,
  url: 'http://example.com/admin/config',
  allowed: check.allowed,
  rule_line: check.line_number,
  rule_text: check.line_text,
  user_agent: 'MyBot'
}
puts "Audit log: #{log_entry.inspect}"
puts

# Example 9: Specific user-agent priority over global rules
puts "9. Specific user-agent rules override global (*) rules:"
puts "-" * 40

robots_txt_multi_agent = <<~ROBOTS
  User-agent: FooBot
  Disallow: /private/
  Allow: /public/

  User-agent: BarBot
  Allow: /admin/
  Disallow: /

  User-agent: *
  Disallow: /admin/
  Allow: /
ROBOTS

puts "Robots.txt has three groups:"
puts "  - FooBot: specific rules (lines 2-3)"
puts "  - BarBot: specific rules (lines 5-6)"
puts "  - *: global fallback rules (lines 8-9)"
puts

# Test with FooBot - should use its specific rules
result_foobot = Robots.query(robots_txt_multi_agent, 'FooBot')

check_admin = result_foobot.check('http://example.com/admin/')
puts "FooBot checking /admin/:"
puts "  Allowed: #{check_admin.allowed}"
puts "  Line: #{check_admin.line_number} - #{check_admin.line_text.inspect}"
puts "  Note: No FooBot rule matches /admin/, defaults to allow"
puts

check_private = result_foobot.check('http://example.com/private/')
puts "FooBot checking /private/:"
puts "  Allowed: #{check_private.allowed}"
puts "  Line: #{check_private.line_number} - #{check_private.line_text.inspect}"
puts "  Note: Matched FooBot's specific Disallow rule"
puts

# Test with BarBot - should use its specific rules
result_barbot = Robots.query(robots_txt_multi_agent, 'BarBot')

check_admin_bar = result_barbot.check('http://example.com/admin/')
puts "BarBot checking /admin/:"
puts "  Allowed: #{check_admin_bar.allowed}"
puts "  Line: #{check_admin_bar.line_number} - #{check_admin_bar.line_text.inspect}"
puts "  Note: BarBot has specific Allow rule for /admin/ (overrides its Disallow: /)"
puts

check_public_bar = result_barbot.check('http://example.com/public/')
puts "BarBot checking /public/:"
puts "  Allowed: #{check_public_bar.allowed}"
puts "  Line: #{check_public_bar.line_number} - #{check_public_bar.line_text.inspect}"
puts "  Note: Matched BarBot's Disallow: / rule"
puts

# Test with BazBot - no specific rules, should fall back to global
result_bazbot = Robots.query(robots_txt_multi_agent, 'BazBot')

check_admin_baz = result_bazbot.check('http://example.com/admin/')
puts "BazBot checking /admin/ (no specific rules, uses global):"
puts "  Allowed: #{check_admin_baz.allowed}"
puts "  Line: #{check_admin_baz.line_number} - #{check_admin_baz.line_text.inspect}"
puts "  Note: BazBot not found, uses global (*) Disallow rule"
puts

check_public_baz = result_bazbot.check('http://example.com/public/')
puts "BazBot checking /public/ (no specific rules, uses global):"
puts "  Allowed: #{check_public_baz.allowed}"
puts "  Line: #{check_public_baz.line_number} - #{check_public_baz.line_text.inspect}"
puts "  Note: BazBot not found, uses global (*) Allow rule"
puts

# Example 10: User-agent extraction and matching
puts "10. User-agent product name extraction:"
puts "-" * 40

# Show that you must extract the product name yourself
raw_user_agent = 'FooBot/2.1 (compatible; +http://example.com/bot)'
extracted = Robots::Utilities.extract_user_agent(raw_user_agent)
puts "Raw user-agent: '#{raw_user_agent}'"
puts "Extracted product name: '#{extracted}'"
puts

# CORRECT: Use extracted product name
result_versioned = Robots.query(robots_txt_multi_agent, extracted)
check_versioned = result_versioned.check('http://example.com/private/')
puts "Using extracted product name '#{extracted}':"
puts "  Checking /private/:"
puts "  Allowed: #{check_versioned.allowed}"
puts "  Line: #{check_versioned.line_number} - #{check_versioned.line_text.inspect}"
puts "  ✓ Correctly matches FooBot's specific rules"
puts

# INCORRECT: Using full user-agent string (won't match)
result_wrong = Robots.query(robots_txt_multi_agent, raw_user_agent)
check_wrong = result_wrong.check('http://example.com/private/')
puts "Using full string '#{raw_user_agent}':"
puts "  Checking /private/:"
puts "  Allowed: #{check_wrong.allowed}"
puts "  Line: #{check_wrong.line_number} - #{check_wrong.line_text.inspect}"
puts "  ✗ Doesn't match FooBot, falls back to global rules"
puts

# Validation helper
puts "Validation:"
puts "  valid_user_agent_to_obey?('FooBot'): #{Robots::RobotsMatcher.valid_user_agent_to_obey?('FooBot')}"
puts "  valid_user_agent_to_obey?('FooBot/2.1'): #{Robots::RobotsMatcher.valid_user_agent_to_obey?('FooBot/2.1')}"
puts "  Note: Only product names [a-zA-Z_-] are valid"
puts

# Test with different casing
result_case = Robots.query(robots_txt_multi_agent, 'foobot')

check_case = result_case.check('http://example.com/private/')
puts "User-agent: 'foobot' (case-insensitive matching)"
puts "  Checking /private/:"
puts "  Allowed: #{check_case.allowed}"
puts "  Line: #{check_case.line_number} - #{check_case.line_text.inspect}"
puts "  Note: Case-insensitive match ('foobot' matches 'FooBot')"
puts

puts "=" * 80
puts "Key UrlCheckResult Attributes:"
puts "=" * 80
puts "• allowed:      Boolean - true if URL is allowed, false if disallowed"
puts "• line_number:  Integer - line number in robots.txt that matched (0 if no match)"
puts "• line_text:    String  - actual text of the matching line (empty if no match)"
puts
puts "Use Cases:"
puts "• Debugging: Understand which rule matched and why"
puts "• User-agent priority: Verify specific agent rules override global rules"
puts "• Logging: Track crawler decisions with rule information"
puts "• Auditing: Maintain compliance records with source rules"
puts "• Testing: Verify specific rules are working as expected"
puts
puts "User-Agent Matching Behavior:"
puts "• Specific agent rules ALWAYS override global (*) rules"
puts "• MUST extract product name before Robots.query(): use Utilities.extract_user_agent()"
puts "  - 'FooBot/2.1 (compatible)' → extract → 'FooBot' → Robots.query()"
puts "• Case-insensitive: 'foobot' matches 'FooBot'"
puts "• Valid characters: [a-zA-Z_-] only (no spaces, slashes, numbers)"
puts "• If specific agent found but no rules match → allow by default"
puts "• If no specific agent found → use global (*) rules"
puts "=" * 80
