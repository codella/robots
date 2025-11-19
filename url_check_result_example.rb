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

# Create a matcher and query for a specific user-agent
matcher = Robots::RobotsMatcher.new
result = matcher.query(robots_txt, 'MyBot')

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

puts "=" * 80
puts "Key UrlCheckResult Attributes:"
puts "=" * 80
puts "• allowed:      Boolean - true if URL is allowed, false if disallowed"
puts "• line_number:  Integer - line number in robots.txt that matched (0 if no match)"
puts "• line_text:    String  - actual text of the matching line (empty if no match)"
puts
puts "Use Cases:"
puts "• Debugging: Understand which rule matched and why"
puts "• Logging: Track crawler decisions with rule information"
puts "• Auditing: Maintain compliance records with source rules"
puts "• Testing: Verify specific rules are working as expected"
puts "=" * 80
