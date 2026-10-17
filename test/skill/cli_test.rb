# frozen_string_literal: true

require 'test_helper'

class CLITest < SkillTest
  def setup
    super
    @repo = FakeRepo.new(@http, 'acme', 'skills')
    @files = {
      'skills/pdf/SKILL.md' => skill_md('pdf'),
      'skills/pdf/scripts/fill.py' => ['print(1)', 0o755],
      'skills/docx/SKILL.md' => skill_md('docx'),
      'skills/broken/SKILL.md' => "nothing here\n"
    }
    @first = @repo.commit(@files, tag: 'v1')
    FileUtils.mkdir_p(File.join(@project, '.claude'))
    File.write(File.join(@project, 'Gemfile'), "gem 'ruby_llm'\n")
  end

  def installed(target, name = 'pdf')
    File.join(@project, target, name)
  end

  def test_add_one_skill_into_detected_targets
    status, out, err = skill('add', 'acme/skills@pdf')

    assert_equal 0, status, err
    assert_equal "✓ Installed pdf → app/skills/pdf, .claude/skills/pdf\n  Recorded in skills.lock\n", out
    assert File.file?(File.join(installed('app/skills'), 'SKILL.md'))
    assert File.file?(File.join(installed('.claude/skills'), 'scripts/fill.py'))
    refute File.executable?(File.join(installed('app/skills'), 'scripts/fill.py'))
    assert_equal "! pdf: dropped the executable bit from 1 file (use --keep-executable)\n", err

    entry = lock['pdf']

    assert_equal({ 'source' => 'acme/skills', 'ref' => nil, 'ref_type' => 'branch', 'commit' => @first,
                   'path' => 'skills/pdf', 'executable' => false, 'targets' => ['.claude/skills', 'app/skills'] },
                 entry.except('digest'))
    assert_match(/\Asha256-\h{64}\z/, entry['digest'])
  end

  def test_add_needs_a_choice_when_a_repository_holds_several_skills
    status, _out, err = skill('add', 'acme/skills')

    assert_equal 2, status
    assert_match(/holds 3 skills: broken, docx, pdf/, err)
    refute_path_exists File.join(@project, 'skills.lock')
  end

  def test_add_all_skips_invalid_skills
    status, out, err = skill('add', 'acme/skills', '--all', '--agent', 'claude')

    assert_equal 0, status, err
    assert_match(%r{Skipping skills/broken}, err)
    assert_equal %w[docx pdf], lock.keys
    assert_match(%r{✓ Installed docx → \.claude/skills/docx}, out)
    refute_path_exists File.join(@project, 'app/skills')
  end

  def test_add_refuses_an_invalid_skill_by_name
    status, _out, err = skill('add', 'acme/skills@broken')

    assert_equal 1, status
    assert_match(/front matter/, err)
  end

  def test_list_option_installs_nothing
    status, out, = skill('add', 'acme/skills', '--list')

    assert_equal 0, status
    assert_match(/pdf  Does pdf things/, out)
    assert_match(/broken  INVALID/, out)
    refute_path_exists File.join(@project, 'skills.lock')
  end

  def test_add_keeps_executable_bits_when_asked
    skill('add', 'acme/skills@pdf', '-x', '--dir', 'vendor/skills')

    assert File.executable?(File.join(@project, 'vendor/skills/pdf/scripts/fill.py'))
    assert lock['pdf']['executable']
  end

  def test_add_at_a_tag_and_a_commit
    @repo.commit(@files.merge('skills/pdf/SKILL.md' => skill_md('pdf', 'Newer.')))
    skill('add', 'acme/skills#v1@pdf')

    assert_equal %w[v1 tag], lock['pdf'].values_at('ref', 'ref_type')
    assert_equal @first, lock['pdf']['commit']

    skill('add', "acme/skills##{@first}@docx")

    assert_equal [@first, 'commit'], lock['docx'].values_at('ref', 'ref_type')
  end

  def test_add_refuses_a_skill_installed_by_hand
    write_tree(installed('app/skills'), 'SKILL.md' => skill_md('pdf'))
    status, _out, err = skill('add', 'acme/skills@pdf')

    assert_equal 1, status
    assert_match(%r{app/skills/pdf exists and was not installed by skill}, err)
    refute_path_exists File.join(installed('.claude/skills'), 'SKILL.md')

    assert_equal 0, skill('add', 'acme/skills@pdf', '--force').first
  end

  def test_add_refuses_a_skill_holding_a_link
    @repo.commit(@files, links: { 'skills/pdf/escape' => '../../../../etc/passwd' })
    status, _out, err = skill('add', 'acme/skills@pdf')

    assert_equal 1, status
    assert_match(/symbolic link/, err)
  end

  def test_add_from_a_local_folder
    write_tree(File.join(@project, 'local'), 'review/SKILL.md' => skill_md('review'))
    status, _out, err = skill('add', './local', '--agent', 'claude')

    assert_equal 0, status, err
    assert_equal({ 'source' => './local', 'ref' => nil, 'ref_type' => 'local', 'commit' => nil,
                   'path' => 'review', 'executable' => false, 'targets' => ['.claude/skills'] },
                 lock['review'].except('digest'))
  end

  def test_update_with_nothing_new
    skill('add', 'acme/skills@pdf')
    status, out, = skill('update')

    assert_equal 0, status
    assert_equal "✓ pdf up to date (main at #{@first[0, 12]})\n", out
    assert_equal(1, @http.requests.count { |url, _| url.include?('codeload') })
  end

  def test_update_shows_a_moved_branch_and_waits_for_yes
    skill('add', 'acme/skills@pdf')
    second = @repo.commit(@files.merge('skills/pdf/SKILL.md' => skill_md('pdf', 'Newer.'),
                                       'skills/pdf/notes.md' => 'new').reject { |path, _| path.end_with?('fill.py') })

    status, out, err = skill('update')

    assert_equal 1, status
    assert_match(%r{pdf: acme/skills #{@first[0, 12]}\.\.#{second[0, 12]}}, out)
    assert_match(%r{https://github.com/acme/skills/compare/}, out)
    assert_match(%r{\+ notes\.md\n  ~ SKILL\.md\n  - scripts/fill\.py}, out)
    assert_match(/update --yes/, err)
    assert_equal @first, lock['pdf']['commit']
    refute_path_exists File.join(installed('app/skills'), 'notes.md')

    assert_equal 0, skill('update', '--dry-run').first
    assert_equal @first, lock['pdf']['commit']

    status, = skill('update', '--yes')

    assert_equal 0, status
    assert_equal second, lock['pdf']['commit']
    assert File.file?(File.join(installed('app/skills'), 'notes.md'))
    refute_path_exists File.join(installed('.claude/skills'), 'scripts/fill.py')
  end

  def test_update_asks_on_a_terminal
    skill('add', 'acme/skills@pdf')
    @repo.commit(@files.merge('skills/pdf/SKILL.md' => skill_md('pdf', 'Newer.')))
    terminal = StringIO.new("y\n")
    def terminal.tty? = true

    status, out, = skill('update', input: terminal)

    assert_equal 0, status
    assert_match(%r{Apply this update\? \[y/N\]}, out)
  end

  def test_update_respects_pinned_commits_and_tags
    skill('add', "acme/skills##{@first}@pdf")
    skill('add', 'acme/skills#v1@docx')
    @repo.commit(@files.merge('skills/pdf/SKILL.md' => skill_md('pdf', 'Newer.')))

    status, out, = skill('update', '--yes')

    assert_equal 0, status
    assert_match(/· pdf pinned to #{@first[0, 12]}, skipped/, out)
    assert_match(/✓ docx up to date \(v1/, out)
    assert_equal @first, lock['pdf']['commit']
  end

  def test_update_warns_when_a_tag_moves
    skill('add', 'acme/skills#v1@pdf')
    moved = @repo.commit(@files.merge('skills/pdf/SKILL.md' => skill_md('pdf', 'Retagged.')), branch: nil, tag: 'v1')

    status, _out, err = skill('update', '--yes')

    assert_equal 0, status, err
    assert_match(/the tag v1 moved from #{@first[0, 12]} to #{moved[0, 12]}/, err)
    assert_equal moved, lock['pdf']['commit']
  end

  def test_update_refuses_to_overwrite_edits
    skill('add', 'acme/skills@pdf')
    File.write(File.join(installed('app/skills'), 'SKILL.md'), 'mine')
    @repo.commit(@files.merge('skills/pdf/SKILL.md' => skill_md('pdf', 'Newer.')))

    status, _out, err = skill('update', '--yes')

    assert_equal 1, status
    assert_match(%r{app/skills/pdf was edited}, err)
    assert_equal 'mine', File.read(File.join(installed('app/skills'), 'SKILL.md'))

    assert_equal 0, skill('update', '--yes', '--force').first
    assert_match(/Newer\./, File.read(File.join(installed('app/skills'), 'SKILL.md')))
  end

  def test_update_of_unknown_skill
    status, _out, err = skill('update', 'nope')

    assert_equal 1, status
    assert_match(/Not installed: nope/, err)
  end

  def test_list_shows_status_and_unmanaged_skills
    skill('add', 'acme/skills@pdf')
    File.write(File.join(installed('app/skills'), 'SKILL.md'), 'mine')
    write_tree(installed('.claude/skills', 'mine'), 'SKILL.md' => skill_md('mine'))

    status, out, = skill('list')

    assert_equal 0, status
    assert_match(%r{\Apdf  acme/skills  branch #{@first[0, 12]}  \.claude/skills, app/skills  edited$}, out)
    assert_match(%r{Not installed by skill:\n  \.claude/skills/mine}, out)

    _status, json, = skill('list', '--json')

    assert_equal 'edited', JSON.parse(json)['pdf']['status']
  end

  def test_list_finds_the_project_root_from_a_subfolder
    skill('add', 'acme/skills@pdf')
    sub = File.join(@project, 'app/models')
    FileUtils.mkdir_p(sub)

    assert_match(/pdf/, skill('list', cwd: sub)[1])
  end

  def test_remove
    skill('add', 'acme/skills@pdf')
    status, out, = skill('remove', 'pdf', '--agent', 'claude')

    assert_equal 0, status
    assert_match(%r{✓ Removed pdf from \.claude/skills/pdf}, out)
    assert_equal ['app/skills'], lock['pdf']['targets']
    refute_path_exists installed('.claude/skills')

    skill('remove', 'pdf')

    refute_path_exists installed('app/skills')
    refute_path_exists File.join(@project, 'skills.lock')
  end

  def test_remove_refuses_edits_and_unmanaged_skills
    skill('add', 'acme/skills@pdf')
    File.write(File.join(installed('app/skills'), 'extra.md'), 'mine')

    assert_equal 1, skill('remove', 'pdf').first
    assert_path_exists installed('.claude/skills')
    assert_equal 0, skill('remove', 'pdf', '--force').first

    write_tree(installed('.claude/skills', 'mine'), 'SKILL.md' => skill_md('mine'))
    status, _out, err = skill('remove', 'mine')

    assert_equal 1, status
    assert_match(/not installed by skill/, err)
  end

  def test_global_scope
    FileUtils.mkdir_p(File.join(@home, '.claude'))
    status, out, err = skill('add', 'acme/skills@pdf', '--global',
                             env: { 'XDG_STATE_HOME' => File.join(@home, 'state') })

    assert_equal 0, status, err
    assert_match(%r{✓ Installed pdf → ~/\.claude/skills/pdf}, out)
    assert File.file?(File.join(@home, '.claude/skills/pdf/SKILL.md'))
    global = JSON.parse(File.read(File.join(@home, 'state/skill/skills.lock')))['skills']

    assert_equal ['~/.claude/skills'], global['pdf']['targets']
    refute_path_exists File.join(@project, 'skills.lock')
  end

  def test_agents_groups
    status, out, err = skill('add', 'acme/skills@pdf', '--agents', 'coding')

    assert_equal 0, status, err
    assert_equal "✓ Installed pdf → .claude/skills/pdf\n  Recorded in skills.lock\n", out
    assert_equal 0, skill('add', 'acme/skills@docx', '--agents', 'all').first
    assert_equal ['.claude/skills', 'app/skills'], lock['docx']['targets']
    assert_equal 0, skill('add', 'acme/skills@docx', '--agents', 'ruby_llm,cursor').first
    assert_equal ['.agents/skills', '.claude/skills', 'app/skills'], lock['docx']['targets']
    assert_equal 0, skill('remove', 'docx', '--agent', 'coding').first
    assert_equal ['app/skills'], lock['docx']['targets']
  end

  def test_find
    @http.route('https://skills.sh/api/search?q=pdf+tools&limit=20',
                body: JSON.generate(skills: [
                                      { id: 'acme/skills/pdf', skillId: 'pdf', source: 'acme/skills', installs: 1500 },
                                      { skillId: "bad\e[31m", source: 'x/y', installs: 9 }
                                    ]))
    status, out, = skill('find', 'pdf', 'tools')

    assert_equal 0, status
    assert_equal "pdf  acme/skills  1.5K installs\n     skill add acme/skills@pdf\n", out
  end

  def test_usage_errors
    assert_equal 2, skill('frobnicate').first
    assert_equal 2, skill('add').first
    assert_equal 2, skill('add', 'acme/skills@pdf', '--agent', 'nope').first
    assert_match(/skill #{Skill::VERSION}/, skill('--version')[1])
  end
end
