#!/usr/bin/env ruby
# frozen_string_literal: true

require 'benchmark'
require_relative 'robots'

robots_txt = <<~ROBOTS
  User-agent: *
  Disallow: /admin/
  Disallow: /private/*.secret$
  Allow: /public/
  Allow: /admin/public/
  Disallow: /temp/

  User-agent: FooBot
  Disallow: /private/
  Allow: /public/

  User-agent: BarBot
  Allow: /admin/
  Disallow: /
ROBOTS

puts "Performance Benchmark: Parse Once vs Parse Every Time"
puts "=" * 70
puts
puts "Testing with #{robots_txt.lines.count} line robots.txt file"
puts

# Create instance (parses once)
robots = Robots.new(robots_txt, 'FooBot')

# Test URLs
urls = [
  'http://example.com/public/page.html',
  'http://example.com/admin/secret.html',
  'http://example.com/admin/public/info.html',
  'http://example.com/private/data.secret',
  'http://example.com/blog/post.html',
  'http://example.com/temp/cache.html'
]

iterations = 1000

puts "Running #{iterations} iterations of checking #{urls.size} URLs..."
puts

Benchmark.bm(20) do |x|
  x.report("check() calls:") do
    iterations.times do
      urls.each { |url| robots.check(url) }
    end
  end
end

total_checks = iterations * urls.size
puts
puts "Total URL checks: #{total_checks}"
puts
puts "✓ With the new optimization:"
puts "  - robots.txt is parsed ONCE during Robots.new()"
puts "  - Each check() call just matches against stored rules"
puts "  - No reparsing = much faster for repeated checks!"
