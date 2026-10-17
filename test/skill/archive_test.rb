# frozen_string_literal: true

require 'test_helper'

class ArchiveTest < SkillTest
  def extract(archive, limits: Skill::Limits.new({}))
    path = File.join(@tmp, 'archive.tar.gz')
    File.binwrite(path, archive)
    into = File.join(@tmp, 'out')
    FileUtils.mkdir_p(into)
    [Skill::Archive.new(limits: limits).extract(path, into), into]
  end

  def test_extracts_below_the_top_folder_and_reads_the_commit
    sha = 'a' * 40
    result, into = extract(tarball('repo-abc', { 'skills/pdf/SKILL.md' => 'hi', 'run.sh' => ['echo', 0o755] },
                                   commit: sha))

    assert_equal sha, result.commit
    assert_equal 'hi', File.read(File.join(into, 'skills/pdf/SKILL.md'))
    assert File.executable?(File.join(into, 'run.sh'))
  end

  def test_records_links_without_writing_them
    result, into = extract(tarball('repo', { 'a.txt' => 'a' }, links: { 'skills/pdf/evil' => '/etc/passwd' }))

    assert_equal ['skills/pdf/evil'], result.links
    refute_path_exists File.join(into, 'skills/pdf/evil')
  end

  def test_refuses_traversal
    archive = tarball('repo', {}, raw: [['repo/../../escape.txt', 'x', '0']])

    assert_raises(Skill::UnsafeError) { extract(archive) }
    refute_path_exists File.join(@tmp, 'escape.txt')
  end

  def test_refuses_absolute_paths_from_pax_headers
    archive = tarball('repo', {}, raw: [['PaxHeader', pax('path', '/tmp/escape.txt'), 'x'], ['repo/ok', 'x', '0']])

    assert_raises(Skill::UnsafeError) { extract(archive) }
  end

  def test_uses_long_names_from_pax_headers
    long = "repo/#{'deep/' * 30}SKILL.md"
    archive = tarball('repo', {}, raw: [['PaxHeader', pax('path', long), 'x'], ['repo/short', 'x', '0']])
    _result, into = extract(archive)

    assert File.file?(File.join(into, long.delete_prefix('repo/')))
  end

  def test_limits
    archive = tarball('repo', { 'a' => 'a' * 2000, 'b' => 'b' })

    bytes = assert_raises(Skill::UnsafeError) { extract(archive, limits: Skill::Limits.new({}, extract_bytes: 1024)) }
    files = assert_raises(Skill::UnsafeError) { extract(archive, limits: Skill::Limits.new({}, extract_files: 1)) }

    assert_includes bytes.message, 'SKILL_MAX_EXTRACT_BYTES'
    assert_includes files.message, 'SKILL_MAX_EXTRACT_FILES'
  end

  def test_refuses_what_is_not_gzip
    assert_raises(Skill::UnsafeError) { extract('not an archive') }
  end
end
