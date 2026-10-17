# frozen_string_literal: true

require 'test_helper'

class LimitsTest < SkillTest
  def test_defaults_fit_large_repositories_and_keep_skills_small
    limits = Skill::Limits.new({})

    assert_equal 512 * 1024 * 1024, limits.download_bytes
    assert_equal 2 * 1024 * 1024 * 1024, limits.extract_bytes
    assert_equal 100_000, limits.extract_files
    assert_equal 16 * 1024 * 1024, limits.skill_bytes
    assert_equal 2_000, limits.skill_files
  end

  def test_variables_raise_or_lower_them
    limits = Skill::Limits.new({ 'SKILL_MAX_DOWNLOAD_BYTES' => '1024', 'SKILL_MAX_SKILL_FILES' => '5' })

    assert_equal 1024, limits.download_bytes
    assert_equal 5, limits.skill_files
  end

  def test_refuses_what_is_not_a_positive_whole_number
    assert_raises(Skill::UsageError) { Skill::Limits.new({ 'SKILL_MAX_DOWNLOAD_BYTES' => '1e9' }) }
    assert_raises(Skill::UsageError) { Skill::Limits.new({ 'SKILL_MAX_EXTRACT_FILES' => '0' }) }
  end

  def test_a_refusal_names_its_variable
    assert_equal 'Too big. Set SKILL_MAX_EXTRACT_BYTES higher for a source you trust',
                 Skill::Limits.exceeded(:extract_bytes, 'Too big')
  end
end
