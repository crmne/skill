# frozen_string_literal: true

require_relative 'lib/skill/version'

Gem::Specification.new do |spec|
  spec.name = 'skill'
  spec.version = Skill::VERSION
  spec.authors = ['Carmine Paolino']
  spec.email = ['carmine@paolino.me']

  spec.summary = 'Install Agent Skills into RubyLLM apps and coding agents.'
  spec.description = <<~TEXT.tr("\n", ' ').strip
    Installs Agent Skills, folders holding a SKILL.md, from GitHub repositories, plugin marketplaces,
    and local folders into RubyLLM's app/skills and the folders Claude Code, Codex, Cursor, and other
    agents read. Records each skill's source and commit in skills.lock, shows what changes before an
    update, and refuses unsafe archives. Run it with `gem exec skill add owner/repo`.
  TEXT
  spec.homepage = 'https://github.com/crmne/skill'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.1'

  spec.metadata = {
    'homepage_uri' => spec.homepage,
    'source_code_uri' => spec.homepage,
    'changelog_uri' => "#{spec.homepage}/blob/main/CHANGELOG.md",
    'bug_tracker_uri' => "#{spec.homepage}/issues",
    'rubygems_mfa_required' => 'true'
  }

  spec.files = Dir['lib/**/*.rb', 'exe/*', 'README.md', 'CHANGELOG.md', 'LICENSE']
  spec.bindir = 'exe'
  spec.executables = ['skill']
  spec.require_paths = ['lib']
end
