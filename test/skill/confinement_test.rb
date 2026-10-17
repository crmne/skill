# frozen_string_literal: true

require 'test_helper'

class ConfinementTest < SkillTest
  def setup
    super
    @repo = FakeRepo.new(@http, 'acme', 'skills')
    @files = { 'skills/pdf/SKILL.md' => skill_md('pdf') }
    @repo.commit(@files)
    @outside = File.join(@tmp, 'outside')
    write_tree(File.join(@outside, 'pdf'), 'SKILL.md' => skill_md('pdf'), 'keep.md' => 'not yours')
    File.write(File.join(@project, 'Gemfile'), "gem 'ruby_llm'\n")
  end

  def point_lock_at(target, root: @project, path: File.join(root, 'skills.lock'))
    data = JSON.parse(File.read(path))
    data['skills']['pdf']['targets'] = [target]
    File.write(path, JSON.generate(data))
  end

  def outside
    [File.read(File.join(@outside, 'pdf/keep.md')), Dir.children(File.join(@outside, 'pdf')).sort]
  end

  def test_update_refuses_a_lockfile_target_climbing_out_with_dot_dot
    skill('add', 'acme/skills@pdf')
    point_lock_at('app/../../outside')
    @repo.commit(@files.merge('skills/pdf/notes.md' => 'new'))

    status, _out, err = skill('update', '--yes')

    assert_equal 1, status
    assert_match(%r{skills\.lock installs into .*/outside, outside the project\. Fix or delete that entry}, err)
    assert_equal ['not yours', %w[SKILL.md keep.md]], outside
  end

  def test_remove_refuses_an_absolute_lockfile_target
    skill('add', 'acme/skills@pdf')
    point_lock_at(@outside)

    status, _out, err = skill('remove', 'pdf', '--force')

    assert_equal 1, status
    assert_match(/outside the project/, err)
    assert_equal ['not yours', %w[SKILL.md keep.md]], outside
    assert_equal [@outside], lock['pdf']['targets']
  end

  def test_remove_all_refuses_before_removing_anything
    skill('add', 'acme/skills@pdf')
    write_tree(File.join(@tmp, 'docs'), 'skills/docx/SKILL.md' => skill_md('docx'))
    skill('add', '../docs/skills/docx', '--agent', 'rubyllm')
    point_lock_at(@outside)

    assert_equal 1, skill('remove', '--all').first
    assert_path_exists File.join(@project, 'app/skills/docx')
    assert_equal ['not yours', %w[SKILL.md keep.md]], outside
  end

  def test_lockfile_targets_through_a_symbolic_link_are_refused
    skill('add', 'acme/skills@pdf')
    File.symlink(@outside, File.join(@project, 'vendor'))
    point_lock_at('vendor')

    status, _out, err = skill('remove', 'pdf', '--force')

    assert_equal 1, status
    assert_match(/installs into vendor, outside the project/, err)
    assert_equal ['not yours', %w[SKILL.md keep.md]], outside
  end

  def test_add_refuses_a_poisoned_entry_from_the_same_source
    skill('add', 'acme/skills@pdf')
    point_lock_at('../outside')

    status, _out, err = skill('add', 'acme/skills@pdf', '--force')

    assert_equal 1, status
    assert_match(/outside the project/, err)
    assert_equal ['not yours', %w[SKILL.md keep.md]], outside
  end

  def test_add_refuses_an_agent_folder_linked_outside
    File.symlink(@outside, File.join(@project, '.claude'))

    status, _out, err = skill('add', 'acme/skills@pdf', '--agent', 'claude', '--force')

    assert_equal 1, status
    assert_match(%r{\.claude/skills leads outside the project}, err)
    refute_path_exists File.join(@outside, 'skills')
    refute_path_exists File.join(@project, 'skills.lock')
  end

  def test_add_refuses_a_dir_outside_the_project
    status, _out, err = skill('add', 'acme/skills@pdf', '--dir', '../outside', '--force')

    assert_equal 1, status
    assert_match(/leads outside the project/, err)
    assert_equal ['not yours', %w[SKILL.md keep.md]], outside
  end

  def test_add_into_a_link_inside_the_project_is_allowed
    FileUtils.mkdir_p(File.join(@project, 'shared'))
    File.symlink(File.join(@project, 'shared'), File.join(@project, 'linked'))

    status, _out, err = skill('add', 'acme/skills@pdf', '--dir', 'linked')

    assert_equal 0, status, err
    assert File.file?(File.join(@project, 'shared/pdf/SKILL.md'))
  end

  def test_list_reports_an_entry_outside_the_project
    skill('add', 'acme/skills@pdf')
    point_lock_at('../outside')

    status, out, = skill('list')

    assert_equal 0, status
    assert_match(/  outside the project$/, out)
  end

  def test_global_targets_stay_in_the_home_folder
    env = { 'XDG_CONFIG_HOME' => File.join(@home, 'config') }
    FileUtils.mkdir_p(File.join(@home, '.claude'))
    skill('add', 'acme/skills@pdf', '--global', env: env)
    point_lock_at(@outside, path: File.join(@home, 'config/skill/skills.lock'))

    status, _out, err = skill('remove', 'pdf', '--global', '--force', env: env)

    assert_equal 1, status
    assert_match(/outside your home folder/, err)
    assert_equal ['not yours', %w[SKILL.md keep.md]], outside
  end

  def test_global_allows_an_agent_folder_the_environment_moved
    config = File.join(@tmp, 'claude-config')
    FileUtils.mkdir_p(config)
    env = { 'CLAUDE_CONFIG_DIR' => config }

    status, _out, err = skill('add', 'acme/skills@pdf', '--global', '--agent', 'claude', env: env)

    assert_equal 0, status, err
    assert File.file?(File.join(config, 'skills/pdf/SKILL.md'))
    assert_equal 0, skill('remove', 'pdf', '--global', env: env).first
  end
end
