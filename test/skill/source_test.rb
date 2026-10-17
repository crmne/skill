# frozen_string_literal: true

require 'test_helper'

class SourceTest < SkillTest
  def parse(text, **options)
    Skill::Source.parse(text, root: @project, **options)
  end

  def test_owner_and_repo
    source = parse('anthropics/skills')

    assert_predicate source, :github?
    assert_equal %w[anthropics skills], [source.owner, source.repo]
    assert_nil source.ref
    assert_equal '', source.subpath
    assert_empty source.skills
  end

  def test_skill_after_at
    assert_equal %w[pdf docx], parse('anthropics/skills@pdf,docx').skills
  end

  def test_subpath
    source = parse('anthropics/skills/skills/pdf')

    assert_equal 'skills/pdf', source.subpath
    assert_equal 'anthropics/skills/skills/pdf', source.to_s
  end

  def test_ref_after_hash_and_skill_after_it
    source = parse('acme/skills#v1.2.0@pdf')

    assert_equal 'v1.2.0', source.ref
    assert_equal ['pdf'], source.skills
  end

  def test_ref_option_wins
    assert_equal 'main', parse('acme/skills#v1', ref: 'main').ref
  end

  def test_github_urls
    source = parse('https://github.com/acme/skills/tree/release/1.0/skills/pdf')

    assert_equal %w[acme skills release], [source.owner, source.repo, source.ref]
    assert_equal '1.0/skills/pdf', source.subpath
    assert_equal 'skills', parse('https://github.com/acme/skills.git').repo
    assert_equal 'acme', parse('github:acme/skills').owner
  end

  def test_local_paths
    source = parse('./my-skills')

    assert_predicate source, :local?
    assert_equal File.join(@project, 'my-skills'), source.path
  end

  def test_refuses_traversal
    assert_raises(Skill::UnsafeError) { parse('acme/skills/../../etc') }
  end

  def test_refuses_other_hosts_and_bad_names
    assert_raises(Skill::UsageError) { parse('https://gitlab.com/acme/skills') }
    assert_raises(Skill::UsageError) { parse('acme') }
    assert_raises(Skill::UsageError) { parse('-acme/skills') }
    assert_raises(Skill::UsageError) { parse('acme/skills#bad..ref') }
  end
end
