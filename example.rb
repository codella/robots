#!/usr/bin/env ruby
# frozen_string_literal: true

# Example usage of the Robots.txt Parser and Matcher Library
#
# This file demonstrates how to use the robots.rb library to parse robots.txt
# files and determine whether URLs can be crawled by specific user agents.

require_relative 'robots'

# Example 1: Basic usage - checking if a URL is allowed
def basic_example
  puts "=== Example 1: Basic Usage ==="

  # Sample robots.txt content
  robots_txt = <<~ROBOTS
    User-agent: *
    Disallow: /admin/
    Disallow: /private/
    Allow: /public/
  ROBOTS

  # Create a matcher instance
  matcher = Robots::RobotsMatcher.new

  # Check various URLs
  urls = [
    'https://example.com/public/page.html',
    'https://example.com/admin/settings',
    'https://example.com/index.html',
    'https://example.com/private/data.json'
  ]

  urls.each do |url|
    allowed = matcher.allowed?(robots_txt, 'MyBot', url)
    puts "  #{url}: #{allowed ? 'ALLOWED' : 'DISALLOWED'}"
  end

  puts
end

# Example 2: User-agent specific rules
def user_agent_example
  puts "=== Example 2: User-Agent Specific Rules ==="

  robots_txt = <<~ROBOTS
    User-agent: GoogleBot
    Disallow: /private/

    User-agent: BingBot
    Disallow: /admin/
    Allow: /admin/public/

    User-agent: *
    Disallow: /
  ROBOTS

  matcher = Robots::RobotsMatcher.new

  url = 'https://example.com/admin/settings'

  ['GoogleBot', 'BingBot', 'OtherBot'].each do |user_agent|
    allowed = matcher.allowed?(robots_txt, user_agent, url)
    puts "  #{user_agent} accessing #{url}: #{allowed ? 'ALLOWED' : 'DISALLOWED'}"
  end

  puts
end

# Example 3: Pattern matching with wildcards
def wildcard_example
  puts "=== Example 3: Wildcard Pattern Matching ==="

  robots_txt = <<~ROBOTS
    User-agent: *
    Disallow: /*.json$
    Disallow: /temp-*
    Allow: /api/*/public
  ROBOTS

  matcher = Robots::RobotsMatcher.new

  urls = [
    'https://example.com/data.json',
    'https://example.com/data.xml',
    'https://example.com/temp-files/doc.txt',
    'https://example.com/api/v1/public',
    'https://example.com/api/v1/private'
  ]

  urls.each do |url|
    allowed = matcher.allowed?(robots_txt, 'MyBot', url)
    puts "  #{url}: #{allowed ? 'ALLOWED' : 'DISALLOWED'}"
  end

  puts
end

# Example 4: Longest match wins (priority rules)
def priority_example
  puts "=== Example 4: Longest Match Wins ==="

  robots_txt = <<~ROBOTS
    User-agent: *
    Disallow: /downloads/
    Allow: /downloads/public/
  ROBOTS

  matcher = Robots::RobotsMatcher.new

  urls = [
    'https://example.com/downloads/file.zip',
    'https://example.com/downloads/public/file.zip'
  ]

  urls.each do |url|
    allowed = matcher.allowed?(robots_txt, 'MyBot', url)
    puts "  #{url}: #{allowed ? 'ALLOWED' : 'DISALLOWED'}"
  end

  puts "  Note: The longer pattern (/downloads/public/) takes priority over /downloads/"
  puts
end

# Example 5: Empty rules and defaults
def default_behavior_example
  puts "=== Example 5: Default Behavior ==="

  # Empty robots.txt - everything allowed
  empty_robots = ""

  # No rules for specific agent - everything allowed
  no_rules_robots = <<~ROBOTS
    User-agent: GoogleBot
    Disallow: /private/

    User-agent: *
  ROBOTS

  matcher = Robots::RobotsMatcher.new
  url = 'https://example.com/page.html'

  allowed = matcher.allowed?(empty_robots, 'MyBot', url)
  puts "  Empty robots.txt: #{allowed ? 'ALLOWED' : 'DISALLOWED'} (default: allow)"

  allowed = matcher.allowed?(no_rules_robots, 'OtherBot', url)
  puts "  No rules for agent: #{allowed ? 'ALLOWED' : 'DISALLOWED'} (default: allow)"

  puts
end

# Example 6: Index.html normalization
def index_normalization_example
  puts "=== Example 6: Index.html Normalization ==="

  robots_txt = <<~ROBOTS
    User-agent: *
    Disallow: /admin/
  ROBOTS

  matcher = Robots::RobotsMatcher.new

  urls = [
    'https://example.com/admin/',
    'https://example.com/admin/index.html',
    'https://example.com/admin/index.htm'
  ]

  urls.each do |url|
    allowed = matcher.allowed?(robots_txt, 'MyBot', url)
    puts "  #{url}: #{allowed ? 'ALLOWED' : 'DISALLOWED'}"
  end

  puts "  Note: /index.html and /index.htm are normalized to /"
  puts
end

# Example 7: Reading from a file
def file_reading_example
  puts "=== Example 7: Reading robots.txt from File ==="

  # Create a temporary robots.txt file
  robots_file = 'example_robots.txt'
  File.write(robots_file, <<~ROBOTS)
    User-agent: *
    Disallow: /private/
    Allow: /

    Sitemap: https://example.com/sitemap.xml
  ROBOTS

  # Read and parse the file
  matcher = Robots::RobotsMatcher.new
  robots_content = File.read(robots_file)

  url = 'https://example.com/private/data'
  allowed = matcher.allowed?(robots_content, 'MyBot', url)

  puts "  Read from #{robots_file}"
  puts "  #{url}: #{allowed ? 'ALLOWED' : 'DISALLOWED'}"

  # Clean up
  File.delete(robots_file)
  puts
end

# Example 8: Checking if a user-agent string is valid
def validation_example
  puts "=== Example 8: User-Agent Validation ==="

  user_agents = [
    'MyBot',
    'Google-Bot',
    'crawler_2024',
    'Invalid Bot!',
    'Bot/1.0',
    'test@bot'
  ]

  user_agents.each do |ua|
    valid = Robots::RobotsMatcher.valid_user_agent_to_obey?(ua)
    puts "  '#{ua}': #{valid ? 'VALID' : 'INVALID'}"
  end

  puts "  Note: Only [a-zA-Z_-] characters are valid in user-agent strings"
  puts
end

# Run all examples
if __FILE__ == $PROGRAM_NAME
  puts "Robots.txt Parser and Matcher - Usage Examples"
  puts "=" * 60
  puts

  basic_example
  user_agent_example
  wildcard_example
  priority_example
  default_behavior_example
  index_normalization_example
  file_reading_example
  validation_example

  puts "=" * 60
  puts "For more information, see RFC 9309: https://www.rfc-editor.org/rfc/rfc9309.html"
end
