#!/usr/bin/env ruby
# frozen_string_literal: true

require 'benchmark/ips'
require_relative 'robots'

# Simple robots.txt (typical small site)
SIMPLE_ROBOTS = <<~ROBOTS
  User-agent: *
  Disallow: /admin/
  Disallow: /private/
  Allow: /public/
ROBOTS

# Medium complexity (typical production site)
MEDIUM_ROBOTS = <<~ROBOTS
  User-agent: Googlebot
  Disallow: /admin/
  Disallow: /private/
  Allow: /api/

  User-agent: Bingbot
  Disallow: /admin/
  Disallow: /internal/
  Allow: /

  User-agent: *
  Disallow: /admin/
  Disallow: /private/
  Disallow: /internal/
  Disallow: /tmp/
  Allow: /public/
  Allow: /api/v1/

  Sitemap: https://example.com/sitemap.xml
ROBOTS

# Complex robots.txt with wildcards (large site)
COMPLEX_ROBOTS = <<~ROBOTS
  User-agent: Googlebot
  Disallow: /admin/*
  Disallow: /*/private/
  Allow: /api/*/public/
  Allow: /static/*.css$
  Allow: /static/*.js$
  Disallow: /search?*sessionid=

  User-agent: Bingbot
  Disallow: /admin/
  Allow: /

  User-agent: *
  Disallow: /admin/
  Disallow: /private/
  Disallow: /temp/
  Disallow: /cache/
  Disallow: /old/
  Disallow: /*.pdf$
  Disallow: /search?
  Allow: /public/
  Allow: /api/

  Sitemap: https://example.com/sitemap.xml
  Sitemap: https://example.com/sitemap-images.xml
ROBOTS

puts "=" * 80
puts "Robots.txt Parser Performance Benchmark"
puts "=" * 80
puts ""

# Benchmark 1: Parsing Performance
puts "1. PARSING PERFORMANCE (initialization)"
puts "-" * 80
Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("parse simple (4 rules)") do
    Robots.new(SIMPLE_ROBOTS, 'TestBot')
  end

  x.report("parse medium (15 rules)") do
    Robots.new(MEDIUM_ROBOTS, 'TestBot')
  end

  x.report("parse complex (20 rules + wildcards)") do
    Robots.new(COMPLEX_ROBOTS, 'Googlebot')
  end

  x.compare!
end

puts ""
puts "2. URL CHECKING THROUGHPUT (simple paths)"
puts "-" * 80

# Pre-parse for URL checking benchmarks
simple_bot = Robots.new(SIMPLE_ROBOTS, 'TestBot')
medium_bot = Robots.new(MEDIUM_ROBOTS, 'TestBot')
complex_bot = Robots.new(COMPLEX_ROBOTS, 'TestBot')

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("check allowed (simple)") do
    simple_bot.check('https://example.com/public/page.html')
  end

  x.report("check disallowed (simple)") do
    simple_bot.check('https://example.com/admin/settings.html')
  end

  x.report("check allowed (medium)") do
    medium_bot.check('https://example.com/public/page.html')
  end

  x.report("check disallowed (medium)") do
    medium_bot.check('https://example.com/admin/settings.html')
  end

  x.compare!
end

puts ""
puts "3. PATTERN MATCHING PERFORMANCE (wildcards vs simple)"
puts "-" * 80

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  # Simple path matching (no wildcards)
  x.report("simple path match") do
    medium_bot.check('https://example.com/admin/page.html')
  end

  # Wildcard pattern matching
  x.report("wildcard match") do
    complex_bot.check('https://example.com/static/style.css')
  end

  # End anchor matching
  x.report("end anchor match") do
    complex_bot.check('https://example.com/document.pdf')
  end

  # Complex wildcard pattern
  x.report("complex wildcard") do
    complex_bot.check('https://example.com/api/v1/public/users')
  end

  x.compare!
end

puts ""
puts "4. REAL-WORLD SCENARIO (parse once, check many)"
puts "-" * 80

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("realistic workflow") do
    bot = Robots.new(MEDIUM_ROBOTS, 'Googlebot')
    bot.check('https://example.com/page1.html')
    bot.check('https://example.com/admin/settings')
    bot.check('https://example.com/api/users')
    bot.check('https://example.com/public/about')
    bot.check('https://example.com/private/data')
  end

  x.report("pre-parsed (5 checks)") do
    medium_bot.check('https://example.com/page1.html')
    medium_bot.check('https://example.com/admin/settings')
    medium_bot.check('https://example.com/api/users')
    medium_bot.check('https://example.com/public/about')
    medium_bot.check('https://example.com/private/data')
  end

  x.compare!
end

puts ""
puts "=" * 80
puts "SUMMARY"
puts "=" * 80
puts "The library uses a 'parse once, check many' strategy:"
puts "  - Parsing happens only during initialization"
puts "  - URL checks are very fast (just rule matching)"
puts "  - Pre-parsed instances can perform 100,000+ checks/second"
puts ""
puts "For best performance:"
puts "  1. Parse robots.txt once and reuse the Robots instance"
puts "  2. Create separate instances for different user-agents"
puts "  3. Simple path patterns are faster than wildcards (but still fast)"
puts "=" * 80
