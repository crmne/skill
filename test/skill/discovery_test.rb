# frozen_string_literal: true

require 'test_helper'

class DiscoveryTest < SkillTest
  def discover(files, options = {})
    root = File.join(@tmp, 'repo')
    write_tree(root, files)
    Skill::Discovery.new(root, **options)
  end

  def names(discovery)
    discovery.candidates.map { |candidate| [candidate.name, candidate.relative] }
  end

  def test_root_skill
    discovery = discover('SKILL.md' => skill_md('solo'), 'skills/other/SKILL.md' => skill_md('other'))

    assert_equal [%w[solo .]], names(discovery)
  end

  def test_skills_folder_with_categories
    discovery = discover('skills/pdf/SKILL.md' => skill_md('pdf'),
                         'skills/office/xlsx/SKILL.md' => skill_md('xlsx'),
                         '.claude/skills/review/SKILL.md' => skill_md('review'),
                         'examples/hidden/SKILL.md' => skill_md('hidden'))

    assert_equal [%w[pdf skills/pdf], %w[review .claude/skills/review], %w[xlsx skills/office/xlsx]], names(discovery)
  end

  def test_shallower_skill_shadows_nested_ones
    discovery = discover('skills/pdf/SKILL.md' => skill_md('pdf'), 'skills/pdf/nested/SKILL.md' => skill_md('nested'))

    assert_equal [%w[pdf skills/pdf]], names(discovery)
  end

  def test_searches_everywhere_when_usual_folders_are_empty
    assert_equal [%w[hidden examples/hidden]], names(discover('examples/hidden/SKILL.md' => skill_md('hidden')))
  end

  def test_subpath
    discovery = discover({ 'skills/pdf/SKILL.md' => skill_md('pdf'), 'skills/docx/SKILL.md' => skill_md('docx') },
                         subpath: 'skills/pdf')

    assert_equal [%w[pdf skills/pdf]], names(discovery)
  end

  def test_invalid_skills_are_reported
    candidate = discover('skills/bad/SKILL.md' => "no front matter\n").candidates.first

    refute_predicate candidate, :valid?
    assert_match(/front matter/, candidate.error)
  end

  def test_claude_marketplace_plugins
    marketplace = {
      name: 'acme', metadata: { pluginRoot: './plugins' },
      plugins: [
        { name: 'docs', source: 'docs', skills: ['./skills/pdf'] },
        { name: 'all', source: './everything' },
        { name: 'remote', source: { source: 'github', repo: 'acme/remote' } }
      ]
    }
    discovery = discover('.claude-plugin/marketplace.json' => JSON.generate(marketplace),
                         'plugins/docs/skills/pdf/SKILL.md' => skill_md('pdf'),
                         'plugins/docs/skills/unlisted/SKILL.md' => skill_md('unlisted'),
                         'everything/skills/xlsx/SKILL.md' => skill_md('xlsx'))

    found = discovery.candidates.to_h { |candidate| [candidate.name, candidate.plugin] }

    assert_equal({ 'pdf' => 'docs', 'xlsx' => 'all' }, found)
    assert_equal [{ 'plugin' => 'remote', 'source' => 'acme/remote' }], discovery.external
  end

  def test_codex_marketplace
    marketplace = { name: 'acme', plugins: [{ name: 'tools', source: { source: 'local', path: './tools' } }] }
    discovery = discover('.agents/plugins/marketplace.json' => JSON.generate(marketplace),
                         'tools/skills/lint/SKILL.md' => skill_md('lint'))

    assert_equal 'tools', discovery.candidates.first.plugin
  end

  def test_plugins_pointing_outside_are_skipped
    marketplace = { name: 'acme', plugins: [{ name: 'evil', source: '../../outside' }] }
    discovery = discover('.claude-plugin/marketplace.json' => JSON.generate(marketplace),
                         'skills/pdf/SKILL.md' => skill_md('pdf'))

    assert_equal [%w[pdf skills/pdf]], names(discovery)
    assert_match(/outside/, discovery.warnings.join)
  end

  def test_symlinked_folders_are_not_followed
    outside = File.join(@tmp, 'outside')
    write_tree(outside, 'SKILL.md' => skill_md('outside'))
    root = File.join(@tmp, 'repo')
    write_tree(root, 'skills/pdf/SKILL.md' => skill_md('pdf'))
    File.symlink(outside, File.join(root, 'skills/outside'))

    assert_equal [%w[pdf skills/pdf]], names(Skill::Discovery.new(root))
  end
end
