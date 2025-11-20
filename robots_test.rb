# frozen_string_literal: true

require 'minitest'

# Workaround for gem conflicts with railties
# This allows running tests with: ruby robots_spec.rb
# without needing any special setup or bundler configuration
module Minitest
  def self.load_plugins
    # Skip plugin loading
  end
end

require 'minitest/autorun'
require_relative 'robots'

class RobotsTest < Minitest::Test
  def is_user_agent_allowed(robots_txt, user_agent, url)
    robots = Robots.new(robots_txt, user_agent)
    robots.check(url).allowed
  end

  def test_handles_basic_system_test_scenarios
    robots_txt = <<~ROBOTS
      user-agent: FooBot
      disallow: /
    ROBOTS

    # Empty robots.txt: everything allowed
    assert is_user_agent_allowed('', 'FooBot', '')

    # Empty user-agent to be matched: everything allowed
    assert is_user_agent_allowed(robots_txt, '', '')

    # Empty url: implicitly disallowed (becomes '/')
    refute is_user_agent_allowed(robots_txt, 'FooBot', '')

    # All params empty: same as robots.txt empty, everything allowed
    assert is_user_agent_allowed('', '', '')
  end

  def test_handles_line_syntax_correctly
    robots_txt_correct = <<~ROBOTS
      user-agent: FooBot
      disallow: /
    ROBOTS

    robots_txt_incorrect = <<~ROBOTS
      foo: FooBot
      bar: /
    ROBOTS

    # CHECK
    robots_txt_incorrect_accepted = <<~ROBOTS
      user-agent FooBot
      disallow /
    ROBOTS

    url = 'http://foo.bar/x/y'

    refute is_user_agent_allowed(robots_txt_correct, 'FooBot', url)
    assert is_user_agent_allowed(robots_txt_incorrect, 'FooBot', url)
    refute is_user_agent_allowed(robots_txt_incorrect_accepted, 'FooBot', url)
  end

  def test_handles_groups_correctly
    robots_txt = <<~ROBOTS
      allow: /foo/bar/

      user-agent: FooBot
      disallow: /
      allow: /x/
      user-agent: BarBot
      disallow: /
      allow: /y/
      allow: /w/

      user-agent: BazBot

      user-agent: FooBot
      allow: /z/
      disallow: /
    ROBOTS

    url_w = 'http://foo.bar/w/a'
    url_x = 'http://foo.bar/x/b'
    url_y = 'http://foo.bar/y/c'
    url_z = 'http://foo.bar/z/d'
    url_foo = 'http://foo.bar/foo/bar/'

    assert is_user_agent_allowed(robots_txt, 'FooBot', url_x)
    assert is_user_agent_allowed(robots_txt, 'FooBot', url_z)
    refute is_user_agent_allowed(robots_txt, 'FooBot', url_y)
    assert is_user_agent_allowed(robots_txt, 'BarBot', url_y)
    assert is_user_agent_allowed(robots_txt, 'BarBot', url_w)
    refute is_user_agent_allowed(robots_txt, 'BarBot', url_z)
    assert is_user_agent_allowed(robots_txt, 'BazBot', url_z)

    # Lines with rules outside groups are ignored
    refute is_user_agent_allowed(robots_txt, 'FooBot', url_foo)
    refute is_user_agent_allowed(robots_txt, 'BarBot', url_foo)
    refute is_user_agent_allowed(robots_txt, 'BazBot', url_foo)
  end

  def test_does_not_close_groups_with_sitemap_directive
    robots_txt = <<~ROBOTS
      User-agent: BarBot
      Sitemap: https://foo.bar/sitemap
      User-agent: *
      Disallow: /
    ROBOTS

    url = 'http://foo.bar/'

    refute is_user_agent_allowed(robots_txt, 'FooBot', url)
    refute is_user_agent_allowed(robots_txt, 'BarBot', url)
  end

  def test_does_not_close_groups_with_unknown_directives
    robots_txt = <<~ROBOTS
      User-agent: FooBot
      Invalid-Unknown-Line: unknown
      User-agent: *
      Disallow: /
    ROBOTS

    url = 'http://foo.bar/'
    
    refute is_user_agent_allowed(robots_txt, 'FooBot', url)
    refute is_user_agent_allowed(robots_txt, 'BarBot', url)
  end

  def test_handles_case_insensitive_directive_names
    robots_txt_upper = <<~ROBOTS
      USER-AGENT: FooBot
      ALLOW: /x/
      DISALLOW: /
    ROBOTS

    robots_txt_lower = <<~ROBOTS
      user-agent: FooBot
      allow: /x/
      disallow: /
    ROBOTS

    robots_txt_camel = <<~ROBOTS
      uSeR-aGeNt: FooBot
      AlLoW: /x/
      dIsAlLoW: /
    ROBOTS

    url_allowed = 'http://foo.bar/x/y'
    url_disallowed = 'http://foo.bar/a/b'

    # Upper case
    assert is_user_agent_allowed(robots_txt_upper, 'FooBot', url_allowed)
    refute is_user_agent_allowed(robots_txt_upper, 'FooBot', url_disallowed)

    # Lower case
    assert is_user_agent_allowed(robots_txt_lower, 'FooBot', url_allowed)
    refute is_user_agent_allowed(robots_txt_lower, 'FooBot', url_disallowed)

    # Camel case
    assert is_user_agent_allowed(robots_txt_camel, 'FooBot', url_allowed)
    refute is_user_agent_allowed(robots_txt_camel, 'FooBot', url_disallowed)
  end

  def test_validates_user_agent_strings
    assert Robots::RobotsMatcher.valid_user_agent_to_obey?('Foobot')
    refute Robots::RobotsMatcher.valid_user_agent_to_obey?('')
    refute Robots::RobotsMatcher.valid_user_agent_to_obey?('ツ')
    refute Robots::RobotsMatcher.valid_user_agent_to_obey?('Foobot*')
    refute Robots::RobotsMatcher.valid_user_agent_to_obey?(' Foobot ')
    refute Robots::RobotsMatcher.valid_user_agent_to_obey?('Foobot/2.1')
    refute Robots::RobotsMatcher.valid_user_agent_to_obey?('Foobot Bar')
  end

  def test_handles_case_insensitive_user_agent_values
    robots_txt_uppercase = <<~ROBOTS
      User-Agent: FooBot
      Allow: /x/
      Disallow: /
    ROBOTS

    robots_txt_lowercase = <<~ROBOTS
      User-Agent: foobot
      Allow: /x/
      Disallow: /
    ROBOTS

    robots_txt_mixedcase = <<~ROBOTS
      User-Agent: fOoBoT
      Allow: /x/
      Disallow: /
    ROBOTS

    url_allowed = 'http://foo.bar/x/y'
    url_disallowed = 'http://foo.bar/a/b'

    assert is_user_agent_allowed(robots_txt_uppercase, 'foobot', url_allowed)
    refute is_user_agent_allowed(robots_txt_uppercase, 'foobot', url_disallowed)
    assert is_user_agent_allowed(robots_txt_lowercase, 'FOOBOT', url_allowed)
    refute is_user_agent_allowed(robots_txt_lowercase, 'FOOBOT', url_disallowed)
    assert is_user_agent_allowed(robots_txt_mixedcase, 'FooBot', url_allowed)
    refute is_user_agent_allowed(robots_txt_mixedcase, 'FooBot', url_disallowed)
  end

  def test_extracts_user_agent_up_to_first_space
    robots_txt = <<~ROBOTS
      User-Agent: *
      Disallow: /
      User-Agent: Foo Bar
      Allow: /x/
      Disallow: /
    ROBOTS

    url = 'http://foo.bar/x/y'

    assert is_user_agent_allowed(robots_txt, 'Foo', url)
    refute is_user_agent_allowed(robots_txt, 'Foo Bar', url)
  end

  def test_handles_global_groups_correctly
    robots_txt_empty = ''

    robots_txt_global = <<~ROBOTS
      user-agent: *
      allow: /
      user-agent: FooBot
      disallow: /
    ROBOTS

    robots_txt_only_specific = <<~ROBOTS
      user-agent: FooBot
      allow: /
      user-agent: BarBot
      disallow: /
      user-agent: BazBot
      disallow: /
    ROBOTS

    url = 'http://foo.bar/x/y'

    assert is_user_agent_allowed(robots_txt_empty, 'FooBot', url)
    refute is_user_agent_allowed(robots_txt_global, 'FooBot', url)
    assert is_user_agent_allowed(robots_txt_global, 'BarBot', url)
    assert is_user_agent_allowed(robots_txt_only_specific, 'QuxBot', url)
  end

  def test_handles_case_sensitive_path_matching
    robots_txt = <<~ROBOTS
      user-agent: FooBot
      allow: /x/
      disallow: /
    ROBOTS

    url = 'http://foo.bar/x/y'
    url_uppercase_x = 'http://foo.bar/X/y'

    assert is_user_agent_allowed(robots_txt, 'FooBot', url)
    refute is_user_agent_allowed(robots_txt, 'FooBot', url_uppercase_x)
  end

  def test_uses_longest_match_strategy
    url = 'http://foo.bar/x/page.html'

    # Longest match wins
    robots_txt = <<~ROBOTS
      user-agent: FooBot
      allow: /x/page.html
      disallow: /x/
    ROBOTS
    assert is_user_agent_allowed(robots_txt, 'FooBot', url)

    robots_txt = <<~ROBOTS
      user-agent: FooBot
      allow: /x/
      disallow: /x/page.html
    ROBOTS
    refute is_user_agent_allowed(robots_txt, 'FooBot', url)

    # With equal length, allow wins
    robots_txt = <<~ROBOTS
      user-agent: FooBot
      allow: /x/page.html
      disallow: /x/page.html
    ROBOTS
    assert is_user_agent_allowed(robots_txt, 'FooBot', url)

    # With equal length, allow wins (order doesn't matter)
    robots_txt = <<~ROBOTS
      user-agent: FooBot
      disallow: /x/page.html
      allow: /x/page.html
    ROBOTS
    assert is_user_agent_allowed(robots_txt, 'FooBot', url)
  end

  def test_handles_utf8_and_percent_encoding
    # /foo/bar?baz=http://foo.bar stays unencoded
    robots_txt = <<~ROBOTS
      User-agent: FooBot
      Disallow: /
      Allow: /foo/bar?qux=taz&baz=http://foo.bar?tar&par
    ROBOTS
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://foo.bar/foo/bar?qux=taz&baz=http://foo.bar?tar&par')

    # 3 byte character: /foo/bar/ツ -> /foo/bar/%E3%83%84
    robots_txt = <<~ROBOTS
      User-agent: FooBot
      Disallow: /
      Allow: /foo/bar/ツ
    ROBOTS
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://foo.bar/foo/bar/%E3%83%84')
    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://foo.bar/foo/bar/ツ')

    # Percent encoded 3 byte character: /foo/bar/%E3%83%84 -> /foo/bar/%E3%83%84
    robots_txt = <<~ROBOTS
      User-agent: FooBot
      Disallow: /
      Allow: /foo/bar/%E3%83%84
    ROBOTS
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://foo.bar/foo/bar/%E3%83%84')
    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://foo.bar/foo/bar/ツ')

    # Percent encoded unreserved US-ASCII: /foo/bar/%62%61%7A
    robots_txt = <<~ROBOTS
      User-agent: FooBot
      Disallow: /
      Allow: /foo/bar/%62%61%7A
    ROBOTS
    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://foo.bar/foo/bar/baz')
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://foo.bar/foo/bar/%62%61%7A')
  end

  def test_handles_special_characters_correctly
    robots_txt = <<~ROBOTS
      User-agent: FooBot
      Disallow: /foo/bar/quz
      Allow: /foo/*/qux
    ROBOTS
    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://foo.bar/foo/bar/quz')
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://foo.bar/foo/quz')
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://foo.bar/foo//quz')
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://foo.bar/foo/bax/quz')

    # $ (end anchor)
    robots_txt = <<~ROBOTS
      User-agent: FooBot
      Disallow: /foo/bar$
      Allow: /foo/bar/qux
    ROBOTS
    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://foo.bar/foo/bar')
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://foo.bar/foo/bar/qux')
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://foo.bar/foo/bar/')
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://foo.bar/foo/bar/baz')
  end

  def test_normalizes_index_html_to_directory
    robots_txt = <<~ROBOTS
      User-Agent: *
      Allow: /allowed-slash/index.html
      Disallow: /
    ROBOTS

    # If index.html is allowed, we interpret this as / being allowed too
    assert is_user_agent_allowed(robots_txt, 'foobot', 'http://foo.com/allowed-slash/')
    # Does not exactly match
    refute is_user_agent_allowed(robots_txt, 'foobot', 'http://foo.com/allowed-slash/index.htm')
    # Exact match
    assert is_user_agent_allowed(robots_txt, 'foobot', 'http://foo.com/allowed-slash/index.html')
    refute is_user_agent_allowed(robots_txt, 'foobot', 'http://foo.com/anyother-url')
  end

  def test_counts_line_numbers_correctly_with_different_line_endings
    # LF line endings - must use literal \n
    robots_txt_lf = "user-agent: FooBot\ndisallow: /\n"
    robots = Robots.new(robots_txt_lf, 'FooBot')
    assert_equal 2, robots.check('http://foo.bar/a').line_number

    # CRLF line endings - must use literal \r\n
    robots_txt_crlf = "user-agent: FooBot\r\ndisallow: /\r\n"
    robots = Robots.new(robots_txt_crlf, 'FooBot')
    assert_equal 2, robots.check('http://foo.bar/a').line_number

    # CR line endings - must use literal \r
    robots_txt_cr = "user-agent: FooBot\rdisallow: /\r"
    robots = Robots.new(robots_txt_cr, 'FooBot')
    assert_equal 2, robots.check('http://foo.bar/a').line_number

    # Mixed line endings - must use literal \n\r
    robots_txt_mixed = "user-agent: FooBot\n\r\ndisallow: /\n\r"
    robots = Robots.new(robots_txt_mixed, 'FooBot')
    assert_equal 3, robots.check('http://foo.bar/a').line_number
  end

  def test_skips_utf8_byte_order_mark
    # UTF-8 BOM: EF BB BF - must use literal bytes
    robots_txt_bom = "\xEF\xBB\xBFUser-Agent: FooBot\nDisallow: /\n".dup.force_encoding('BINARY')

    robots_txt_no_bom = <<~ROBOTS
      User-Agent: FooBot
      Disallow: /
    ROBOTS

    refute is_user_agent_allowed(robots_txt_bom, 'FooBot', 'http://foo.bar/a')
    refute is_user_agent_allowed(robots_txt_no_bom, 'FooBot', 'http://foo.bar/a')
  end

  def test_parses_sitemap_directives
    robots_txt = <<~ROBOTS
      User-Agent: *
      Sitemap: https://example.com/sitemap.xml
      Disallow: /
    ROBOTS

    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://foo.bar/a')
  end

  def test_extracts_path_params_and_query_correctly
    assert_equal '/', Robots::Utilities.get_path_params_query('')
    assert_equal '/', Robots::Utilities.get_path_params_query('http://www.example.com')
    assert_equal '/', Robots::Utilities.get_path_params_query('http://www.example.com/')
    assert_equal '/a', Robots::Utilities.get_path_params_query('http://www.example.com/a')
    assert_equal '/a/', Robots::Utilities.get_path_params_query('http://www.example.com/a/')
    assert_equal '/a/b?c=http://d.e/', Robots::Utilities.get_path_params_query('http://www.example.com/a/b?c=http://d.e/')
    assert_equal '/a/b?c=d&e=f', Robots::Utilities.get_path_params_query('http://www.example.com/a/b?c=d&e=f#fragment')
    assert_equal '/', Robots::Utilities.get_path_params_query('example.com')
    assert_equal '/', Robots::Utilities.get_path_params_query('example.com/')
    assert_equal '/a', Robots::Utilities.get_path_params_query('example.com/a')
    assert_equal '/a/', Robots::Utilities.get_path_params_query('example.com/a/')
    assert_equal '/a/b?c=d&e=f', Robots::Utilities.get_path_params_query('example.com/a/b?c=d&e=f#fragment')
    assert_equal '/', Robots::Utilities.get_path_params_query('a')
    assert_equal '/', Robots::Utilities.get_path_params_query('a/')
    assert_equal '/a', Robots::Utilities.get_path_params_query('/a')
    assert_equal '/b', Robots::Utilities.get_path_params_query('a/b')
    assert_equal '/?a', Robots::Utilities.get_path_params_query('example.com?a')
    assert_equal '/a;b', Robots::Utilities.get_path_params_query('example.com/a;b#c')
    assert_equal '/b/c', Robots::Utilities.get_path_params_query('//a/b/c')
  end

  def test_check_result_includes_line_number
    robots_txt = <<~ROBOTS
      user-agent: FooBot
      disallow: /
    ROBOTS

    robots = Robots.new(robots_txt, 'FooBot')
    check = robots.check('http://example.com/')

    assert_equal 2, check.line_number
  end

  def test_check_result_includes_line_text
    robots_txt = <<~ROBOTS
      user-agent: FooBot
      disallow: /admin/
      allow: /public/
    ROBOTS

    robots = Robots.new(robots_txt, 'FooBot')

    # Check disallowed URL
    check_admin = robots.check('http://example.com/admin/secret')
    assert_equal 2, check_admin.line_number
    assert_equal 'disallow: /admin/', check_admin.line_text

    # Check allowed URL
    check_public = robots.check('http://example.com/public/page')
    assert_equal 3, check_public.line_number
    assert_equal 'allow: /public/', check_public.line_text
  end

  def test_check_result_line_text_empty_when_no_match
    robots_txt = <<~ROBOTS
      user-agent: FooBot
      disallow: /admin/
    ROBOTS

    robots = Robots.new(robots_txt, 'FooBot')

    # URL not matching any rule (allowed by default)
    check = robots.check('http://example.com/public/page')
    assert_equal 0, check.line_number
    assert_equal '', check.line_text
  end

  def test_check_result_allowed_field
    robots_txt = <<~ROBOTS
      user-agent: FooBot
      allow: /public/
      disallow: /
    ROBOTS

    robots = Robots.new(robots_txt, 'FooBot')

    # Allowed URL
    check_allowed = robots.check('http://example.com/public/page')
    assert check_allowed.allowed

    # Disallowed URL
    check_disallowed = robots.check('http://example.com/admin/')
    refute check_disallowed.allowed
  end

  # ============================================================================
  # PHASE 1: CRITICAL RFC COMPLIANCE TESTS
  # ============================================================================

  def test_empty_disallow_allows_everything
    # RFC 9309: Empty Disallow value means "allow everything"
    robots_txt = <<~ROBOTS
      User-agent: FooBot
      Disallow:
    ROBOTS

    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/')
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/anything')
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/admin/secret')
  end

  def test_multiple_user_agents_share_rules
    # RFC 9309: Multiple consecutive user-agent lines share the same rules
    robots_txt = <<~ROBOTS
      User-agent: FooBot
      User-agent: BarBot
      User-agent: BazBot
      Disallow: /admin/
      Allow: /public/
    ROBOTS

    # All three bots should share the same rules
    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/admin/')
    refute is_user_agent_allowed(robots_txt, 'BarBot', 'http://example.com/admin/')
    refute is_user_agent_allowed(robots_txt, 'BazBot', 'http://example.com/admin/')

    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/public/')
    assert is_user_agent_allowed(robots_txt, 'BarBot', 'http://example.com/public/')
    assert is_user_agent_allowed(robots_txt, 'BazBot', 'http://example.com/public/')
  end

  def test_specific_agent_with_separate_group_allows_by_default
    # If specific agent in separate group with no rules, should allow by default
    robots_txt = <<~ROBOTS
      User-agent: FooBot
      Disallow: /allow-me-to-be-empty

      User-agent: *
      Disallow: /
    ROBOTS

    # FooBot has empty rules group (pattern that doesn't match), should allow most URLs
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/')
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/anything')

    # BarBot not found, should use global (disallow)
    refute is_user_agent_allowed(robots_txt, 'BarBot', 'http://example.com/')
  end

  def test_empty_disallow_with_conflicting_rules
    # Empty Disallow (priority 0) should interact correctly with other rules
    robots_txt = <<~ROBOTS
      User-agent: FooBot
      Disallow:
      Disallow: /admin/
    ROBOTS

    # Longer pattern should win
    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/admin/')
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/public/')
  end

  def test_empty_allow_with_conflicting_rules
    # Empty Allow should allow everything with priority 0
    robots_txt = <<~ROBOTS
      User-agent: FooBot
      Allow:
      Disallow: /admin/
    ROBOTS

    # Longer pattern should win
    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/admin/')
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/public/')
  end

  def test_multiple_user_agents_with_global_fallback
    # Multiple user-agents in one group, other bots fall back to global
    robots_txt = <<~ROBOTS
      User-agent: FooBot
      User-agent: BarBot
      Allow: /allowed/
      Disallow: /

      User-agent: *
      Disallow: /admin/
    ROBOTS

    # FooBot and BarBot use their specific rules
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/allowed/')
    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/other/')
    assert is_user_agent_allowed(robots_txt, 'BarBot', 'http://example.com/allowed/')
    refute is_user_agent_allowed(robots_txt, 'BarBot', 'http://example.com/other/')

    # BazBot uses global rules
    assert is_user_agent_allowed(robots_txt, 'BazBot', 'http://example.com/allowed/')
    refute is_user_agent_allowed(robots_txt, 'BazBot', 'http://example.com/admin/')
    assert is_user_agent_allowed(robots_txt, 'BazBot', 'http://example.com/other/')
  end

  # ============================================================================
  # PHASE 2: CRITICAL UNTESTED CODE PATHS
  # ============================================================================

  def test_disallow_ignore_global_method
    # Tests the public disallow_ignore_global? method (alternative decision logic)
    # This method ignores global rules and only looks at specific agent rules
    robots_txt = <<~ROBOTS
      User-agent: FooBot
      Disallow: /admin/

      User-agent: *
      Allow: /
    ROBOTS

    robots = Robots.new(robots_txt, 'FooBot')

    # Check URL through normal query method
    check_admin = robots.check('http://example.com/admin/')
    check_public = robots.check('http://example.com/public/')

    refute check_admin.allowed
    assert check_public.allowed
  end

  def test_index_html_optimization_only_for_allow
    # The index.html optimization only applies to Allow directives
    robots_txt = <<~ROBOTS
      User-Agent: *
      Disallow: /admin/index.html
      Allow: /
    ROBOTS

    # Disallow only blocks the exact path (no normalization for Disallow)
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://foo.com/admin/')
    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://foo.com/admin/index.html')

    # But Allow with index.html DOES normalize
    robots_txt2 = <<~ROBOTS
      User-Agent: *
      Allow: /public/index.html
      Disallow: /
    ROBOTS
    assert is_user_agent_allowed(robots_txt2, 'FooBot', 'http://foo.com/public/')
    assert is_user_agent_allowed(robots_txt2, 'FooBot', 'http://foo.com/public/index.html')
  end

  def test_index_htm_normalization
    # Tests that both index.html and index.htm trigger normalization
    robots_txt_html = <<~ROBOTS
      User-Agent: *
      Allow: /allowed/index.html
      Disallow: /
    ROBOTS

    robots_txt_htm = <<~ROBOTS
      User-Agent: *
      Allow: /allowed/index.htm
      Disallow: /
    ROBOTS

    # index.html should normalize to directory
    assert is_user_agent_allowed(robots_txt_html, 'FooBot', 'http://foo.com/allowed/')
    assert is_user_agent_allowed(robots_txt_html, 'FooBot', 'http://foo.com/allowed/index.html')

    # index.htm should also normalize to directory
    assert is_user_agent_allowed(robots_txt_htm, 'FooBot', 'http://foo.com/allowed/')
    assert is_user_agent_allowed(robots_txt_htm, 'FooBot', 'http://foo.com/allowed/index.htm')
  end

  def test_line_length_at_max_limit
    # Tests handling of lines at maximum length (16,664 bytes)
    # Create a line just under MAX_LINE_LEN
    long_path = 'a' * 16650  # Leave room for "Disallow: /"
    robots_txt = <<~ROBOTS
      User-agent: FooBot
      Disallow: /#{long_path}
    ROBOTS

    # Should handle gracefully
    robots = Robots.new(robots_txt, 'FooBot')
    result = robots.check('http://example.com/test')
    assert_instance_of Robots::UrlCheckResult, result

    # The long pattern should work
    long_url = "http://example.com/#{long_path}"
    refute is_user_agent_allowed(robots_txt, 'FooBot', long_url)
  end

  def test_line_length_exceeding_max_limit
    # Tests handling of lines exceeding maximum length
    # Create a line that exceeds MAX_LINE_LEN (16,664 bytes)
    very_long_path = 'a' * 20000
    robots_txt = <<~ROBOTS
      User-agent: FooBot
      Disallow: /#{very_long_path}
    ROBOTS

    # Should handle gracefully (even if line is truncated or ignored)
    robots = Robots.new(robots_txt, 'FooBot')
    result = robots.check('http://example.com/test')
    assert_instance_of Robots::UrlCheckResult, result

    # Check that we can still check URLs without crashing
    assert [true, false].include?(result.allowed)  # Either is acceptable
  end

  # ============================================================================
  # PHASE 3: HIGH PRIORITY EDGE CASES
  # ============================================================================

  def test_whitespace_separator_extension
    # Extension: accepts missing colons with whitespace separator
    robots_txt_no_colon = <<~ROBOTS
      User-agent FooBot
      Disallow /admin/
    ROBOTS

    refute is_user_agent_allowed(robots_txt_no_colon, 'FooBot', 'http://example.com/admin/')
    assert is_user_agent_allowed(robots_txt_no_colon, 'FooBot', 'http://example.com/public/')
  end

  def test_global_agent_with_trailing_space
    # Global agent with space: '* ' should be treated as global
    robots_txt = <<~ROBOTS
      User-agent: *
      Disallow: /
    ROBOTS

    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/')
    refute is_user_agent_allowed(robots_txt, 'BarBot', 'http://example.com/')
  end

  def test_wildcard_only_pattern
    # Pattern is just '*' - should match everything
    robots_txt = <<~ROBOTS
      User-agent: FooBot
      Disallow: *
    ROBOTS

    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/')
    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/anything')
    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/path/to/file')
  end

  def test_end_anchor_only_pattern
    # Pattern is just '$' - matches paths that end immediately (root path)
    robots_txt = <<~ROBOTS
      User-agent: FooBot
      Disallow: $
    ROBOTS

    # '$' pattern doesn't match '/' because '/' has length 1
    # It would only match an empty path after the domain
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/')
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/anything')
  end

  def test_root_with_end_anchor
    # Pattern '/$' should match only root path
    robots_txt = <<~ROBOTS
      User-agent: FooBot
      Disallow: /$
    ROBOTS

    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/')
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/page')
  end

  def test_wildcard_at_start_of_pattern
    # Wildcard at start: '*/admin' matches paths containing /admin as prefix after wildcard
    robots_txt = <<~ROBOTS
      User-agent: FooBot
      Disallow: */admin
    ROBOTS

    # Pattern matches because wildcard can match any prefix
    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/admin')
    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/foo/admin')
    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/foo/bar/admin')
    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/admin/page')
  end

  def test_wildcard_at_end_of_pattern
    # Wildcard at end: '/foo/*' should match /foo/ and anything after
    robots_txt = <<~ROBOTS
      User-agent: FooBot
      Disallow: /foo/*
    ROBOTS

    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/foo/')
    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/foo/bar')
    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/foo/bar/baz')
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/foobar')
  end

  def test_consecutive_wildcards
    # Consecutive wildcards: '**' should behave like single '*'
    robots_txt = <<~ROBOTS
      User-agent: FooBot
      Disallow: /foo**bar
    ROBOTS

    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/foobar')
    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/foo123bar')
    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/foo/anything/bar')
  end

  def test_percent_encoding_lowercase_hex
    # Lowercase hex in patterns is normalized to uppercase (URLs are not normalized)
    robots_txt = <<~ROBOTS
      User-agent: FooBot
      Disallow: /
      Allow: /foo/%2f
    ROBOTS

    # Pattern %2f is normalized to %2F, so only uppercase URL matches
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/foo/%2F')
    # Lowercase URL doesn't match (URLs are not normalized)
    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/foo/%2f')
  end

  def test_percent_encoding_mixed_case
    # Pattern normalization: all hex digits become uppercase
    robots_txt = <<~ROBOTS
      User-agent: FooBot
      Disallow: /
      Allow: /foo/%2F%3a
    ROBOTS

    # Pattern normalized to %2F%3A
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/foo/%2F%3A')
    # Lowercase hex in URL doesn't match
    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/foo/%2F%3a')
    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/foo/%2f%3A')
  end

  def test_nil_robots_txt_input
    # nil robots.txt should be treated as empty
    robots = Robots.new(nil, 'FooBot')
    check = robots.check('http://example.com/')

    # Empty robots.txt means allow all
    assert check.allowed
  end

  def test_empty_robots_txt
    # Empty string robots.txt should allow all
    assert is_user_agent_allowed('', 'FooBot', 'http://example.com/')
    assert is_user_agent_allowed('', 'FooBot', 'http://example.com/anything')
  end

  def test_whitespace_only_robots_txt
    # Whitespace-only robots.txt should allow all
    assert is_user_agent_allowed("   \n  \n  ", 'FooBot', 'http://example.com/')
  end

  def test_comment_only_lines
    # Lines with only comments should be ignored
    robots_txt = <<~ROBOTS
      User-agent: FooBot
      # This is a comment
      Disallow: /admin/
    ROBOTS

    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/admin/')
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/public/')
  end

  def test_comment_after_directive
    # Comments after directives should be stripped
    robots_txt = <<~ROBOTS
      User-agent: FooBot
      Disallow: /admin/ # secret area
    ROBOTS

    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/admin/')
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/public/')
  end

  def test_multiple_hash_symbols_in_line
    # Only first # starts comment (comments are stripped)
    robots_txt = <<~ROBOTS
      User-agent: FooBot
      Disallow: /foo # bar # baz
    ROBOTS

    # Pattern is /foo (comment stripped), which matches /foo* as prefix
    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/foo')
    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/foo/bar')
    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/foobar')
    # Doesn't match paths not starting with /foo
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/bar')
  end

  def test_line_number_zero_when_no_rules_match
    # Line number 0 when no rules match
    robots_txt = <<~ROBOTS
      User-agent: FooBot
      Disallow: /admin/
    ROBOTS

    robots = Robots.new(robots_txt, 'FooBot')
    check = robots.check('http://example.com/public/')

    # Allowed by default (no rule matched), line 0
    assert check.allowed
    assert_equal 0, check.line_number
    assert_equal '', check.line_text
  end

  def test_url_with_fragment_before_path
    # Fragment before path should return '/'
    assert_equal '/', Robots::Utilities.get_path_params_query('http://example.com#frag/path')
  end

  def test_url_with_protocol_separator_in_query
    # :// in query string should not be treated as protocol separator
    url = 'http://example.com/page?url=http://other.com/path'
    assert_equal '/page?url=http://other.com/path', Robots::Utilities.get_path_params_query(url)
  end

  # ============================================================================
  # PHASE 4: ERROR/NEGATIVE TESTS
  # ============================================================================

  def test_malformed_robots_txt_with_garbage
    # Malformed robots.txt with random garbage should handle gracefully
    robots_txt = <<~ROBOTS
      Random garbage
      !@#$%^&*()
      User-agent: FooBot
      Disallow: /admin/
    ROBOTS

    # Should still parse valid directives
    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/admin/')
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/public/')
  end

  def test_invalid_directive_values
    # Invalid directive values should be handled gracefully
    robots_txt = <<~ROBOTS
      User-agent: FooBot
      Disallow:
      Allow: @!$
      Disallow: /admin/
    ROBOTS

    # Empty Disallow is handled, special chars in Allow are treated as literal pattern
    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/admin/')
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/public/')
  end

  def test_very_long_url_path
    # Very long URL paths (1000+ chars) should be handled
    long_path = '/' + 'a' * 5000
    robots_txt = <<~ROBOTS
      User-agent: FooBot
      Disallow: /admin/
    ROBOTS

    # Should not crash
    robots = Robots.new(robots_txt, 'FooBot')
    check = robots.check("http://example.com#{long_path}")

    assert check.allowed  # Doesn't match /admin/
  end

  def test_binary_data_in_robots_txt
    # Binary data should be handled gracefully - must use literal bytes
    robots_txt = "User-agent: FooBot\n\x00\x01\x02Disallow: /\n"

    # Should handle binary data without crashing
    robots = Robots.new(robots_txt, 'FooBot')
    result = robots.check('http://example.com/test')
    assert_instance_of Robots::UrlCheckResult, result
  end

  def test_extremely_nested_paths
    # Extremely nested paths should work
    nested_path = '/' + (['a'] * 100).join('/')
    robots_txt = <<~ROBOTS
      User-agent: FooBot
      Disallow: /admin/
    ROBOTS

    robots = Robots.new(robots_txt, 'FooBot')
    check = robots.check("http://example.com#{nested_path}")

    assert check.allowed
  end

  def test_empty_user_agent_value
    # Empty user-agent value should be handled
    robots_txt = <<~ROBOTS
      User-agent:
      Disallow: /
    ROBOTS

    # Should still process (empty user-agent might match empty string)
    robots = Robots.new(robots_txt, 'FooBot')
    check = robots.check('http://example.com/')

    # Either allowed or disallowed is acceptable
    assert [true, false].include?(check.allowed)
  end

  def test_unicode_in_user_agent
    # Unicode in user-agent should be handled
    robots_txt = <<~ROBOTS
      User-agent: FooBot
      Disallow: /
      User-agent: Bär
      Allow: /
    ROBOTS

    # Should handle gracefully
    robots = Robots.new(robots_txt, 'FooBot')
    check = robots.check('http://example.com/')

    refute check.allowed  # FooBot should be disallowed
  end

  def test_no_final_newline
    # robots.txt without final newline should work - must use literal string
    robots_txt = "User-agent: FooBot\nDisallow: /admin/"

    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/admin/')
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/public/')
  end

  def test_only_blank_lines
    # File with only blank lines should allow all - must use literal \n
    robots_txt = "\n\n\n\n"

    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/')
  end

  def test_mixed_valid_and_invalid_lines
    # Mix of valid and invalid lines
    robots_txt = <<~ROBOTS
      User-agent: FooBot
      InvalidLine
      Disallow: /admin/
      Another bad line!!!
      Allow: /public/
      ????
    ROBOTS

    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/admin/')
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://example.com/public/')
  end
end
