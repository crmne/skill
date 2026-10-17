# frozen_string_literal: true

module Skill
  # Decides which folders a command installs to, lists, or updates: the
  # folders of the agents and groups named with +--agents+, the folders
  # named with +--dir+, or else the ones the project or home folder shows
  # signs of.
  class Targets
    # One folder skills are installed into, and the agents that read it.
    Target = Struct.new(:path, :label, :agents, keyword_init: true)

    # Files and folders in a project that show it uses an agent, beyond the
    # agent's own skills folder.
    PROJECT_SIGNS = {
      'claude-code' => %w[.claude CLAUDE.md],
      'codex' => %w[.codex AGENTS.md],
      'cursor' => %w[.cursor .cursorrules],
      'gemini-cli' => %w[.gemini GEMINI.md],
      'github-copilot' => %w[.github/copilot-instructions.md],
      'windsurf' => %w[.windsurf .windsurfrules]
    }.freeze

    # Folders in the home folder that show an agent is installed, for agents
    # whose global skills folder is shared with others.
    GLOBAL_SIGNS = {
      'codex' => ['CODEX_HOME', '~/.codex'],
      'cline' => [nil, '~/.cline'],
      'zed' => [nil, '~/.config/zed'],
      'warp' => [nil, '~/.warp']
    }.freeze

    SHARED_GLOBAL_DIRS = %w[~/.agents/skills {config}/agents/skills].freeze
    FALLBACK = 'universal'
    RUBY_LLM = 'rubyllm'

    # Names +--agents+ takes for several agents at once: +all+, every agent
    # detected (RubyLLM's +app/skills+ included in a RubyLLM project), and
    # +coding+, every coding agent detected, never RubyLLM. Both fall back to
    # the shared +.agents/skills+ folder when they detect none. +*+ is every
    # agent +skill agents+ lists.
    GROUPS = %w[all coding *].freeze

    attr_reader :root, :home, :env

    # +root+ is the project folder, ignored with +global+.
    def initialize(root:, home:, env:, global: false)
      @root = File.expand_path(root)
      @home = File.expand_path(home)
      @env = env
      @global = global
    end

    def global?
      @global
    end

    # Returns the Targets for +agents+ (names, aliases, or GROUPS) and
    # +dirs+, or the detected ones (the +all+ group) when both are empty.
    # Folders several agents share are returned once.
    def resolve(agents: [], dirs: [])
      agents = ['all'] if agents.empty? && dirs.empty?
      list = agents_named(agents).filter_map { |agent| target_for(agent, strict: true) }
      list += dirs.map { |dir| Target.new(path: File.expand_path(dir, base), label: dir, agents: []) }
      merge(list)
    end

    # Returns the Targets of every agent whose folder exists, for listing.
    def existing
      merge(Agents.all.filter_map { |agent| target_for(agent) }.select { |target| File.directory?(target.path) })
    end

    # Returns the agents the project or home folder shows signs of, or the
    # shared +.agents/skills+ folder when it shows none. With +coding+,
    # leaves RubyLLM out.
    def detected_agents(coding: false)
      found = Agents.all.select { |agent| global? ? installed?(agent) : used_in_project?(agent) }
      found.reject! { |agent| agent.key == RUBY_LLM } if coding
      found.empty? ? [Agents.fetch(FALLBACK)] : found
    end

    # Returns +path+ as the lockfile records it: relative to the project, or
    # starting with +~+ in the home folder.
    def display(path)
      expanded = File.expand_path(path)
      if !global? && inside?(expanded, root)
        expanded == root ? '.' : expanded.delete_prefix("#{root}/")
      elsif inside?(expanded, home)
        expanded == home ? '~' : "~/#{expanded.delete_prefix("#{home}/")}"
      else
        expanded
      end
    end

    # Returns the absolute path of a folder the lockfile recorded.
    def expand(path)
      File.expand_path(path.to_s.sub(%r{\A~(?=/|\z)}, home), base)
    end

    # Returns the Boundary skills install inside: the project, or with
    # +global+ the home folder and any global agent folder the environment
    # moved elsewhere.
    def boundary
      @boundary ||= if global?
                      folders = Agents.all.filter_map { |agent| Agents.global_path(agent, env: env, home: home) }
                      Boundary.new([home, *folders], name: 'your home folder')
                    else
                      Boundary.new([root], name: 'the project')
                    end
    end

    private

    def base
      global? ? home : root
    end

    def agents_named(names)
      names.flat_map do |name|
        case name.to_s.strip.downcase
        when '*' then Agents.all.select { |agent| global? ? agent.global? : true }
        when 'all' then detected_agents
        when 'coding' then detected_agents(coding: true)
        else [Agents.fetch(name)]
        end
      end.uniq
    end

    def target_for(agent, strict: false)
      path = global? ? Agents.global_path(agent, env: env, home: home) : File.join(root, agent.project_dir)
      if path.nil?
        raise UsageError, "#{agent.name} has no global skills folder; install it in a project" if strict

        return
      end
      Target.new(path: path, label: display(path), agents: [agent.name])
    end

    def merge(targets)
      targets.group_by(&:path).map do |path, group|
        Target.new(path: path, label: display(path), agents: group.flat_map(&:agents).uniq)
      end
    end

    def used_in_project?(agent)
      return ruby_llm? if agent.key == RUBY_LLM
      return File.directory?(File.join(root, agent.project_dir)) if agent.key == FALLBACK

      (PROJECT_SIGNS.fetch(agent.key, []) + own_signs(agent)).any? { |sign| File.exist?(File.join(root, sign)) }
    end

    # An agent's own folder shows it is used, unless other tools share it
    # (+.agents+) or it is too common a name to mean anything (+skills+).
    def own_signs(agent)
      dir = agent.project_dir
      return [] if dir.start_with?('.agents/') || !dir.include?('/')

      dir.start_with?('.') ? [dir.split('/').first] : [dir]
    end

    def ruby_llm?
      return true if File.directory?(File.join(root, 'app/skills'))

      %w[Gemfile.lock gems.locked Gemfile gems.rb].any? do |file|
        path = File.join(root, file)
        File.file?(path) && File.read(path, 256 * 1024).match?(/^\s*(?:gem\s+["']ruby_llm["']|ruby_llm \()/)
      end
    end

    def installed?(agent)
      return false unless agent.global?

      if GLOBAL_SIGNS.key?(agent.key)
        variable, default = GLOBAL_SIGNS[agent.key]
        dir = variable && !env[variable].to_s.empty? ? env[variable] : default
        return File.directory?(expand(dir))
      end
      return false if SHARED_GLOBAL_DIRS.include?(agent.global_dir)

      File.directory?(File.dirname(Agents.global_path(agent, env: env, home: home)))
    end

    def inside?(path, folder)
      path == folder || path.start_with?("#{folder}/")
    end
  end
end
