# frozen_string_literal: true

require 'json'

module Skill
  # Finds the skills in a repository or folder, where vercel-labs/skills
  # looks for them: a +SKILL.md+ at the top, the conventional skill
  # folders (+skills/+, the agents' own folders) up to three levels deep,
  # the plugins of a Claude Code, Codex, or Cursor marketplace file, and,
  # when those hold nothing, the whole tree.
  class Discovery
    # A folder holding a +SKILL.md+. +manifest+ is +nil+ and +error+ says
    # why when the +SKILL.md+ is invalid.
    Candidate = Struct.new(:path, :relative, :manifest, :error, :plugin, keyword_init: true) do
      def valid?
        !manifest.nil?
      end

      def name
        manifest ? manifest.name : File.basename(relative)
      end
    end

    CONTAINERS = %w[skills skills/.curated skills/.experimental skills/.system].freeze
    MARKETPLACES = %w[.claude-plugin/marketplace.json .agents/plugins/marketplace.json
                      .cursor-plugin/marketplace.json].freeze
    PLUGINS = %w[.claude-plugin/plugin.json .codex-plugin/plugin.json .cursor-plugin/plugin.json].freeze
    SKIPPED = %w[.git node_modules vendor/bundle].freeze
    CONTAINER_DEPTH = 3
    FULL_DEPTH = 8

    # External plugins a marketplace lists in other repositories, which
    # need a +skill add+ of their own.
    attr_reader :external, :warnings

    def initialize(root, subpath: '', full_depth: false)
      @root = File.realpath(root.to_s)
      @base = inside!(File.join(@root, Source.clean_path(subpath)))
      @full_depth = full_depth
      @found = {}
      @external = []
      @warnings = []
    end

    # Returns every Candidate, ordered by name.
    def candidates
      @candidates ||= begin
        search
        @found.values.sort_by { |candidate| [candidate.name, candidate.relative] }
      end
    end

    private

    def search
      raise NotFoundError, "#{relative(@base)} is not a folder" unless File.directory?(@base) && !File.symlink?(@base)
      return add(@base) if skill?(@base)

      plugins
      (CONTAINERS + Agents.all.map(&:project_dir)).uniq.each do |container|
        walk(File.join(@base, container), CONTAINER_DEPTH)
      end
      walk(@base, FULL_DEPTH) if @found.empty? || @full_depth
    end

    def walk(dir, depth, plugin: nil)
      return unless File.directory?(dir) && !File.symlink?(dir)
      return add(dir, plugin: plugin) if skill?(dir)
      return if depth.zero?

      Dir.children(dir).sort.each do |child|
        next if SKIPPED.include?(child) || SKIPPED.include?(relative(File.join(dir, child)))

        walk(File.join(dir, child), depth - 1, plugin: plugin)
      end
    end

    def skill?(dir)
      file = File.join(dir, Manifest::FILE)
      File.file?(file) && !File.symlink?(file)
    end

    def add(dir, plugin: nil)
      key = relative(dir)
      return if @found.key?(key)

      manifest = Manifest.load(dir)
      if (other = @found.values.find { |candidate| candidate.valid? && candidate.name == manifest.name })
        @warnings << "Two skills are named #{manifest.name}: #{other.relative} and #{key}. Using #{other.relative}"
        return
      end
      @found[key] = Candidate.new(path: dir, relative: key, manifest: manifest, plugin: plugin)
    rescue InvalidSkillError => e
      @found[key] = Candidate.new(path: dir, relative: key, error: e.message.delete_prefix("#{@root}/"), plugin: plugin)
    end

    def plugins
      MARKETPLACES.each { |file| marketplace(File.join(@base, file)) }
      PLUGINS.each do |file|
        data = json(File.join(@base, file))
        plugin_skills(@base, data['skills'], data['name']) if data
      end
    end

    def marketplace(file)
      data = json(file)
      return unless data && data['plugins'].is_a?(Array)

      root = data.dig('metadata', 'pluginRoot').to_s
      data['plugins'].grep(Hash).each { |entry| marketplace_plugin(entry, root) }
    end

    def marketplace_plugin(entry, plugin_root)
      name = entry['name'].to_s
      source = entry['source']
      source = source['path'] if source.is_a?(Hash) && [nil, 'local'].include?(source['source'])
      unless source.nil? || source.is_a?(String)
        @external << { 'plugin' => name, 'source' => external_source(source) }
        return
      end

      path = source.to_s
      path = File.join(plugin_root, path) unless plugin_root.empty? || path.start_with?('./', '../')
      plugin_skills(File.join(@base, Source.clean_path(path)), entry['skills'], name)
    rescue UnsafeError
      @warnings << "The #{name} plugin points outside the repository; skipped"
    end

    def plugin_skills(plugin_dir, skills, name)
      plugin_dir = inside!(plugin_dir)
      paths = skills.is_a?(Array) ? skills.grep(String) : []
      return walk(File.join(plugin_dir, 'skills'), CONTAINER_DEPTH, plugin: name) if paths.empty?

      paths.each { |path| walk(inside!(File.join(plugin_dir, Source.clean_path(path))), 1, plugin: name) }
    rescue UnsafeError
      @warnings << "The #{name} plugin points outside the repository; skipped"
    end

    def external_source(source)
      repo = source['repo'] || source['url'].to_s[%r{github\.com[/:]([\w.-]+/[\w.-]+?)(?:\.git)?/?\z}, 1]
      repo ? [repo, source['path']].compact.join('/') : source['url'] || source['source']
    end

    def json(file)
      return unless File.file?(file) && !File.symlink?(file)

      data = JSON.parse(File.read(file, encoding: 'UTF-8').delete_prefix("\u{FEFF}"))
      data.is_a?(Hash) ? data : nil
    rescue JSON::ParserError
      @warnings << "#{relative(file)} is not valid JSON; skipped"
      nil
    end

    def inside!(path)
      expanded = File.expand_path(path)
      expanded = File.realpath(expanded) if File.exist?(expanded)
      return expanded if expanded == @root || expanded.start_with?("#{@root}/")

      raise UnsafeError, "#{path} leaves #{@root}"
    end

    def relative(path)
      path == @root ? '.' : path.delete_prefix("#{@root}/")
    end
  end
end
