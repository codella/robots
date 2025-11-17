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
    matcher = Robots::RobotsMatcher.new
    matcher.one_agent_allowed_by_robots?(robots_txt, user_agent, url)
  end

  def test_handles_basic_system_test_scenarios
    robots_txt = "user-agent: FooBot\ndisallow: /\n"

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
    robots_txt_correct = "user-agent: FooBot\ndisallow: /\n"
    robots_txt_incorrect = "foo: FooBot\nbar: /\n"
    robots_txt_incorrect_accepted = "user-agent FooBot\ndisallow /\n"
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
    robots_txt_uppercase = "User-Agent: FooBot\nAllow: /x/\nDisallow: /\n"
    robots_txt_lowercase = "User-Agent: foobot\nAllow: /x/\nDisallow: /\n"
    robots_txt_mixedcase = "User-Agent: fOoBoT\nAllow: /x/\nDisallow: /\n"

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
    robots_txt = "User-Agent: *\nDisallow: /\nUser-Agent: Foo Bar\nAllow: /x/\nDisallow: /\n"
    url = 'http://foo.bar/x/y'

    assert is_user_agent_allowed(robots_txt, 'Foo', url)
    refute is_user_agent_allowed(robots_txt, 'Foo Bar', url)
  end

  def test_handles_global_groups_correctly
    robots_txt_empty = ''
    robots_txt_global = "user-agent: *\nallow: /\nuser-agent: FooBot\ndisallow: /\n"
    robots_txt_only_specific = "user-agent: FooBot\nallow: /\nuser-agent: BarBot\ndisallow: /\nuser-agent: BazBot\ndisallow: /\n"
    url = 'http://foo.bar/x/y'

    assert is_user_agent_allowed(robots_txt_empty, 'FooBot', url)
    refute is_user_agent_allowed(robots_txt_global, 'FooBot', url)
    assert is_user_agent_allowed(robots_txt_global, 'BarBot', url)
    assert is_user_agent_allowed(robots_txt_only_specific, 'QuxBot', url)
  end

  def test_handles_case_sensitive_path_matching
    robots_txt = "user-agent: FooBot\nallow: /x/\ndisallow: /\n"
    url = 'http://foo.bar/x/y'
    url_uppercase_x = 'http://foo.bar/X/y'

    assert is_user_agent_allowed(robots_txt, 'FooBot', url)
    refute is_user_agent_allowed(robots_txt, 'FooBot', url_uppercase_x)
  end

  def test_uses_longest_match_strategy
    url = 'http://foo.bar/x/page.html'

    # Longest match wins
    robots_txt = "user-agent: FooBot\nallow: /x/page.html\ndisallow: /x/\n"
    assert is_user_agent_allowed(robots_txt, 'FooBot', url)

    robots_txt = "user-agent: FooBot\nallow: /x/\ndisallow: /x/page.html\n"
    refute is_user_agent_allowed(robots_txt, 'FooBot', url)

    # With equal length, allow wins
    robots_txt = "user-agent: FooBot\nallow: /x/page.html\ndisallow: /x/page.html\n"
    assert is_user_agent_allowed(robots_txt, 'FooBot', url)

    # With equal length, allow wins (order doesn't matter)
    robots_txt = "user-agent: FooBot\ndisallow: /x/page.html\nallow: /x/page.html\n"
    assert is_user_agent_allowed(robots_txt, 'FooBot', url)
  end

  def test_handles_utf8_and_percent_encoding
    # /foo/bar?baz=http://foo.bar stays unencoded
    robots_txt = "User-agent: FooBot\nDisallow: /\nAllow: /foo/bar?qux=taz&baz=http://foo.bar?tar&par\n"
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://foo.bar/foo/bar?qux=taz&baz=http://foo.bar?tar&par')

    # 3 byte character: /foo/bar/ツ -> /foo/bar/%E3%83%84
    robots_txt = "User-agent: FooBot\nDisallow: /\nAllow: /foo/bar/ツ\n"
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://foo.bar/foo/bar/%E3%83%84')
    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://foo.bar/foo/bar/ツ')

    # Percent encoded 3 byte character: /foo/bar/%E3%83%84 -> /foo/bar/%E3%83%84
    robots_txt = "User-agent: FooBot\nDisallow: /\nAllow: /foo/bar/%E3%83%84\n"
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://foo.bar/foo/bar/%E3%83%84')
    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://foo.bar/foo/bar/ツ')

    # Percent encoded unreserved US-ASCII: /foo/bar/%62%61%7A
    robots_txt = "User-agent: FooBot\nDisallow: /\nAllow: /foo/bar/%62%61%7A\n"
    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://foo.bar/foo/bar/baz')
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://foo.bar/foo/bar/%62%61%7A')
  end

  def test_handles_special_characters_correctly
    robots_txt = "User-agent: FooBot\nDisallow: /foo/bar/quz\nAllow: /foo/*/qux\n"
    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://foo.bar/foo/bar/quz')
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://foo.bar/foo/quz')
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://foo.bar/foo//quz')
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://foo.bar/foo/bax/quz')

    # $ (end anchor)
    robots_txt = "User-agent: FooBot\nDisallow: /foo/bar$\nAllow: /foo/bar/qux\n"
    refute is_user_agent_allowed(robots_txt, 'FooBot', 'http://foo.bar/foo/bar')
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://foo.bar/foo/bar/qux')
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://foo.bar/foo/bar/')
    assert is_user_agent_allowed(robots_txt, 'FooBot', 'http://foo.bar/foo/bar/baz')
  end

  def test_normalizes_index_html_to_directory
    robots_txt = "User-Agent: *\nAllow: /allowed-slash/index.html\nDisallow: /\n"

    # If index.html is allowed, we interpret this as / being allowed too
    assert is_user_agent_allowed(robots_txt, 'foobot', 'http://foo.com/allowed-slash/')
    # Does not exactly match
    refute is_user_agent_allowed(robots_txt, 'foobot', 'http://foo.com/allowed-slash/index.htm')
    # Exact match
    assert is_user_agent_allowed(robots_txt, 'foobot', 'http://foo.com/allowed-slash/index.html')
    refute is_user_agent_allowed(robots_txt, 'foobot', 'http://foo.com/anyother-url')
  end

  def test_counts_line_numbers_correctly_with_different_line_endings
    matcher = Robots::RobotsMatcher.new

    # LF line endings
    robots_txt_lf = "user-agent: FooBot\ndisallow: /\n"
    matcher.one_agent_allowed_by_robots?(robots_txt_lf, 'FooBot', 'http://foo.bar/a')
    assert_equal 2, matcher.matching_line

    # CRLF line endings
    robots_txt_crlf = "user-agent: FooBot\r\ndisallow: /\r\n"
    matcher.one_agent_allowed_by_robots?(robots_txt_crlf, 'FooBot', 'http://foo.bar/a')
    assert_equal 2, matcher.matching_line

    # CR line endings
    robots_txt_cr = "user-agent: FooBot\rdisallow: /\r"
    matcher.one_agent_allowed_by_robots?(robots_txt_cr, 'FooBot', 'http://foo.bar/a')
    assert_equal 2, matcher.matching_line

    # Mixed line endings
    robots_txt_mixed = "user-agent: FooBot\n\r\ndisallow: /\n\r"
    matcher.one_agent_allowed_by_robots?(robots_txt_mixed, 'FooBot', 'http://foo.bar/a')
    assert_equal 3, matcher.matching_line
  end

  def test_skips_utf8_byte_order_mark
    # UTF-8 BOM: EF BB BF
    robots_txt_bom = "\xEF\xBB\xBFUser-Agent: FooBot\nDisallow: /\n".dup.force_encoding('BINARY')
    robots_txt_no_bom = "User-Agent: FooBot\nDisallow: /\n"

    refute is_user_agent_allowed(robots_txt_bom, 'FooBot', 'http://foo.bar/a')
    refute is_user_agent_allowed(robots_txt_no_bom, 'FooBot', 'http://foo.bar/a')
  end

  def test_parses_sitemap_directives
    robots_txt = "User-Agent: *\nSitemap: https://example.com/sitemap.xml\nDisallow: /\n"
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
end
