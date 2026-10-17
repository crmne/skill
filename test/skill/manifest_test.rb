# frozen_string_literal: true

require 'test_helper'

class ManifestTest < SkillTest
  def manifest(content, folder: 'pdf')
    dir = File.join(@tmp, folder)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, 'SKILL.md'), content)
    Skill::Manifest.load(dir)
  end

  def test_reads_name_and_description
    skill = manifest(skill_md('pdf', 'Reads PDFs.', "metadata:\n  internal: true\n"))

    assert_equal 'pdf', skill.name
    assert_equal 'Reads PDFs.', skill.description
    assert_predicate skill, :internal?
  end

  def test_requires_front_matter
    error = assert_raises(Skill::InvalidSkillError) { manifest("# No front matter\n") }
    assert_match(/front matter/, error.message)
  end

  def test_requires_name_and_description
    assert_raises(Skill::InvalidSkillError) { manifest("---\ndescription: x\n---\n") }
    assert_raises(Skill::InvalidSkillError) { manifest("---\nname: pdf\n---\n") }
  end

  def test_name_format_and_length
    assert_raises(Skill::InvalidSkillError) { manifest(skill_md('PDF')) }
    assert_raises(Skill::InvalidSkillError) { manifest(skill_md('pdf--tools')) }
    assert_raises(Skill::InvalidSkillError) { manifest(skill_md('a' * 65)) }
  end

  def test_description_length
    assert_raises(Skill::InvalidSkillError) { manifest(skill_md('pdf', 'x' * 1025)) }
  end

  def test_invalid_yaml_and_wrong_types
    assert_raises(Skill::InvalidSkillError) { manifest("---\nname: [pdf\n---\n") }
    assert_raises(Skill::InvalidSkillError) { manifest("---\nname: pdf\ndescription: 3\n---\n") }
    assert_raises(Skill::InvalidSkillError) { manifest("---\n- a\n---\n") }
  end

  def test_missing_file
    assert_raises(Skill::InvalidSkillError) { Skill::Manifest.load(@tmp) }
  end
end
