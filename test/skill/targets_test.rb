# frozen_string_literal: true

require 'test_helper'

class TargetsTest < SkillTest
  def targets(global: false, env: {})
    Skill::Targets.new(root: @project, home: @home, env: env, global: global)
  end

  def labels(list)
    list.map(&:label)
  end

  def test_falls_back_to_the_shared_agents_folder
    assert_equal ['.agents/skills'], labels(targets.resolve)
  end

  def test_detects_ruby_llm_from_the_lockfile_and_claude_code
    File.write(File.join(@project, 'Gemfile.lock'), "GEM\n  specs:\n    ruby_llm (2.2.0)\n")
    Dir.mkdir(File.join(@project, '.claude'))

    assert_equal ['app/skills', '.claude/skills'], labels(targets.resolve)
  end

  def test_detects_ruby_llm_from_app_skills
    FileUtils.mkdir_p(File.join(@project, 'app/skills'))

    assert_equal ['app/skills'], labels(targets.resolve)
  end

  def test_agents_sharing_a_folder_resolve_once
    list = targets.resolve(agents: %w[codex cursor])

    assert_equal ['.agents/skills'], labels(list)
    assert_equal %w[Codex Cursor], list.first.agents
  end

  def test_groups
    File.write(File.join(@project, 'Gemfile'), "gem 'ruby_llm'\n")

    assert_equal ['app/skills', '.agents/skills'], labels(targets.resolve(agents: %w[all universal]))
    assert_equal ['.agents/skills'], labels(targets.resolve(agents: ['coding']))
    Dir.mkdir(File.join(@project, '.claude'))

    assert_equal ['app/skills', '.claude/skills'], labels(targets.resolve(agents: ['all']))
    assert_equal ['.claude/skills'], labels(targets.resolve(agents: ['Coding']))
    assert_equal ['.claude/skills', 'app/skills'], labels(targets.resolve(agents: %w[coding ruby_llm]))
  end

  def test_global_groups_have_no_ruby_llm
    FileUtils.mkdir_p(File.join(@home, '.claude'))

    assert_equal ['~/.claude/skills'], labels(targets(global: true).resolve(agents: ['all']))
    assert_equal ['~/.claude/skills'], labels(targets(global: true).resolve(agents: ['coding']))
  end

  def test_dirs
    assert_equal ['vendor/skills'], labels(targets.resolve(dirs: [File.join(@project, 'vendor/skills')]))
  end

  def test_unknown_agent
    assert_raises(Skill::UsageError) { targets.resolve(agents: ['nope']) }
  end

  def test_global_detection_and_environment
    FileUtils.mkdir_p(File.join(@home, '.claude'))
    FileUtils.mkdir_p(File.join(@home, '.codex'))
    list = targets(global: true).resolve

    assert_equal ['~/.claude/skills', '~/.agents/skills'], labels(list)
    custom = targets(global: true, env: { 'CLAUDE_CONFIG_DIR' => File.join(@home, 'claude') })

    assert_equal ['~/claude/skills'], labels(custom.resolve(agents: ['claude']))
  end

  def test_project_only_agents_refuse_global
    assert_raises(Skill::UsageError) { targets(global: true).resolve(agents: ['rubyllm']) }
  end

  def test_display_and_expand_round_trip
    list = targets

    assert_equal 'app/skills', list.display(File.join(@project, 'app/skills'))
    assert_equal File.join(@project, 'app/skills'), list.expand('app/skills')
    assert_equal File.join(@home, '.claude/skills'), list.expand('~/.claude/skills')
  end
end
