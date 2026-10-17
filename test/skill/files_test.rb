# frozen_string_literal: true

require 'test_helper'

class TreeTest < SkillTest
  def test_digest_diff_and_executables
    before_dir = File.join(@tmp, 'before')
    after_dir = File.join(@tmp, 'after')
    write_tree(before_dir, 'SKILL.md' => 'a', 'old.md' => 'x', 'run.sh' => ['echo', 0o755])
    write_tree(after_dir, 'SKILL.md' => 'b', 'new.md' => 'y', 'run.sh' => ['echo', 0o644])
    before = Skill::Tree.read(before_dir)
    after = Skill::Tree.read(after_dir)

    diff = after.diff_from(before)

    assert_equal [['new.md'], %w[SKILL.md run.sh], ['old.md']], [diff.added, diff.changed, diff.removed]
    assert_equal ['SKILL.md'], after.diff_from(before, executable: false).changed
    assert_equal ['run.sh'], before.executables
    refute_equal before.digest, Skill::Tree.read(before_dir).digest(executable: false)
  end

  def test_refuses_links_and_large_skills
    dir = File.join(@tmp, 'skill')
    write_tree(dir, 'SKILL.md' => 'a' * 100)

    assert_raises(Skill::UnsafeError) { Skill::Tree.read(dir, limits: Skill::Limits.new({}, skill_bytes: 10)) }
    File.symlink('/etc/passwd', File.join(dir, 'link'))
    assert_raises(Skill::UnsafeError) { Skill::Tree.read(dir) }
  end
end

class LockfileTest < SkillTest
  def test_round_trip_sorted_without_nil_plugins
    path = File.join(@project, 'skills.lock')
    lock = Skill::Lockfile.new(path)
    lock['zeta'] = { 'source' => 'a/b', 'targets' => %w[b a a], 'plugin' => nil, 'commit' => 'c' }
    lock['alpha'] = { source: 'a/b', targets: ['x'], ignored: true }
    lock.save

    data = JSON.parse(File.read(path))

    assert_equal %w[alpha zeta], data['skills'].keys
    assert_equal %w[a b], data['skills']['zeta']['targets']
    refute data['skills']['zeta'].key?('plugin')
    refute data['skills']['alpha'].key?('ignored')
    assert_equal 'c', Skill::Lockfile.new(path)['zeta']['commit']
  end

  def test_deletes_itself_when_empty
    path = File.join(@project, 'skills.lock')
    lock = Skill::Lockfile.new(path)
    lock['a'] = { 'source' => 'a/b', 'targets' => [] }
    lock.save
    lock.delete('a')
    lock.save

    refute_path_exists path
  end

  def test_refuses_broken_or_newer_lockfiles
    path = File.join(@project, 'skills.lock')
    File.write(path, "<<<<<<< HEAD\n")
    assert_raises(Skill::Error) { Skill::Lockfile.new(path) }
    File.write(path, JSON.generate(version: 99, skills: {}))
    assert_raises(Skill::Error) { Skill::Lockfile.new(path) }
    File.write(path, JSON.generate(version: 1, skills: { '../evil' => { source: 'a/b' } }))
    assert_raises(Skill::Error) { Skill::Lockfile.new(path) }
  end

  def test_global_path
    assert_equal '/state/skill/skills.lock',
                 Skill::Lockfile.global_path(env: { 'XDG_STATE_HOME' => '/state' }, home: '/h')
    assert_equal '/h/.local/state/skill/skills.lock', Skill::Lockfile.global_path(env: {}, home: '/h')
  end
end

class InstallerTest < SkillTest
  def copy(name, files, targets, executable: false)
    source = File.join(@tmp, "source-#{name}-#{rand(1000)}")
    write_tree(source, files)
    Skill::Installer::Copy.new(name: name, tree: Skill::Tree.read(source), targets: targets, executable: executable)
  end

  def test_installs_into_every_target_dropping_executable_bits
    targets = [File.join(@project, 'a'), File.join(@project, 'b')]
    Skill::Installer.new.install([copy('pdf', { 'SKILL.md' => 'x', 'run.sh' => ['echo', 0o755] }, targets)])

    targets.each { |target| assert_equal 'x', File.read(File.join(target, 'pdf/SKILL.md')) }
    refute File.executable?(File.join(targets.first, 'pdf/run.sh'))
    assert_empty Dir.glob(File.join(targets.first, '.skill-*'))
  end

  def test_keeps_executable_bits_when_asked
    target = File.join(@project, 'a')
    Skill::Installer.new.install([copy('pdf', { 'run.sh' => ['echo', 0o755] }, [target], executable: true)])

    assert File.executable?(File.join(target, 'pdf/run.sh'))
  end

  def test_a_failure_leaves_earlier_installs_in_place
    target = File.join(@project, 'a')
    Skill::Installer.new.install([copy('pdf', { 'SKILL.md' => 'old' }, [target])])
    good = copy('pdf', { 'SKILL.md' => 'new' }, [target])
    bad = copy('docx', { 'SKILL.md' => 'new' }, [target])
    FileUtils.rm_rf(bad.tree.root)

    assert_raises(SystemCallError) { Skill::Installer.new.install([good, bad]) }
    assert_equal 'old', File.read(File.join(target, 'pdf/SKILL.md'))
    refute_path_exists File.join(target, 'docx')
    assert_empty Dir.glob(File.join(target, '.skill-*'))
  end

  def test_replaces_a_symlinked_skill_without_touching_its_target
    shared = File.join(@project, '.agents/skills/pdf')
    write_tree(shared, 'SKILL.md' => 'shared')
    target = File.join(@project, '.claude/skills')
    FileUtils.mkdir_p(target)
    File.symlink(shared, File.join(target, 'pdf'))
    Skill::Installer.new.install([copy('pdf', { 'SKILL.md' => 'mine' }, [target])])

    assert_equal 'shared', File.read(File.join(shared, 'SKILL.md'))
    assert_equal 'mine', File.read(File.join(target, 'pdf/SKILL.md'))
    refute File.symlink?(File.join(target, 'pdf'))
  end

  def test_refuses_names_that_leave_the_target
    assert_raises(Skill::UnsafeError) { Skill::Installer.destination(@project, '../evil') }
  end
end
