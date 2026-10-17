# frozen_string_literal: true

require 'test_helper'

class ScopeTest < SkillTest
  def setup
    super
    FakeRepo.new(@http, 'acme', 'skills').commit({ 'skills/pdf/SKILL.md' => skill_md('pdf') })
    FileUtils.mkdir_p(File.join(@home, '.claude'))
    @env = { 'XDG_STATE_HOME' => File.join(@home, '.local/state') }
    @global_lock = File.join(@home, '.local/state/skill/skills.lock')
  end

  def folder(path)
    File.join(@home, path).tap { |full| FileUtils.mkdir_p(full) }
  end

  def test_outside_a_project_installs_globally
    downloads = folder('Downloads')

    status, out, err = skill('add', 'acme/skills@pdf', env: @env, cwd: downloads)

    assert_equal 0, status, err
    recorded = "  Recorded in ~/.local/state/skill/skills.lock\n"

    assert_equal "✓ Installed pdf → ~/.claude/skills/pdf (global)\n#{recorded}", out
    assert_path_exists File.join(@home, '.claude/skills/pdf/SKILL.md')
    assert_path_exists @global_lock
    refute_path_exists File.join(downloads, 'skills.lock')
    assert_match(%r{\Apdf  acme/skills  .*~/\.claude/skills$}, skill('list', env: @env, cwd: downloads)[1])
    assert_equal 0, skill('remove', 'pdf', env: @env, cwd: @home).first
    refute_path_exists File.join(@home, '.claude/skills/pdf')
  end

  def test_the_home_folder_is_never_a_project
    write_tree(@home, '.git/HEAD' => "ref: refs/heads/main\n", 'AGENTS.md' => '')

    skill('add', 'acme/skills@pdf', env: @env, cwd: @home)

    assert_path_exists @global_lock
    refute_path_exists File.join(@home, 'skills.lock')
  end

  def test_project_overrides_outside_a_project
    downloads = folder('Downloads')

    status, out, err = skill('add', 'acme/skills@pdf', '--project', env: @env, cwd: downloads)

    assert_equal 0, status, err
    assert_equal "✓ Installed pdf → .agents/skills/pdf\n  Recorded in skills.lock\n", out
    assert_path_exists File.join(downloads, 'skills.lock')
    refute_path_exists @global_lock
  end

  def test_agent_instructions_alone_make_a_project
    app = folder('work/app')
    File.write(File.join(app, 'CLAUDE.md'), '')
    sub = folder('work/app/docs')

    status, out, err = skill('add', 'acme/skills@pdf', env: @env, cwd: sub)

    assert_equal 0, status, err
    assert_match(%r{→ \.claude/skills/pdf\n}, out)
    assert_path_exists File.join(app, 'skills.lock')
    refute_path_exists @global_lock
  end

  def test_a_gemfile_above_wins_over_agent_folders_below
    write_tree(folder('work/app'), 'Gemfile' => "gem 'ruby_llm'\n")
    write_tree(folder('work/app/engine'), 'AGENTS.md' => '')

    skill('add', 'acme/skills@pdf', env: @env, cwd: File.join(@home, 'work/app/engine'))

    assert_path_exists File.join(@home, 'work/app/skills.lock')
    assert_path_exists File.join(@home, 'work/app/app/skills/pdf')
  end
end
