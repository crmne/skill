# frozen_string_literal: true

module Skill
  # Where a command works: a project (found from the current folder) or the
  # home folder, with its Targets and its Lockfile. Knows whether a folder
  # it would replace or delete is still what it installed.
  class Workspace
    ROOT_MARKERS = %w[skills.lock Gemfile gems.rb .git package.json].freeze
    AGENT_MARKERS = %w[.agents .claude .codex .cursor .gemini .windsurf AGENTS.md CLAUDE.md GEMINI.md].freeze

    attr_reader :root, :targets, :lock

    # Opens the project around +cwd+, or the home folder with +global+.
    # With +global+ +nil+, uses the home folder when +cwd+ is in no
    # project, the way a person running it there expects.
    def self.open(cwd:, home:, env:, global:, limits:)
      project = project_root(cwd, home)
      global = project.nil? if global.nil?
      root = global ? home : project || cwd
      lock = global ? Lockfile.global_path(env: env, home: home) : File.join(root, Lockfile::NAME)
      new(root: root, targets: Targets.new(root: root, home: home, env: env, global: global),
          lock: Lockfile.new(lock), limits: limits)
    end

    # Returns the nearest folder from +cwd+ up holding a lockfile, a
    # Gemfile, a git repository, or a package.json, else the nearest
    # holding an agent's folder or instructions (+.claude+, +AGENTS.md+...),
    # else +nil+. The home folder, where agents keep their global folders,
    # is never a project, and the search stops there.
    def self.project_root(cwd, home)
      agent_folder = nil
      directory = cwd
      until directory == home
        return directory if ROOT_MARKERS.any? { |marker| File.exist?(File.join(directory, marker)) }

        agent_folder ||= directory if AGENT_MARKERS.any? { |marker| File.exist?(File.join(directory, marker)) }
        parent = File.dirname(directory)
        break if parent == directory

        directory = parent
      end
      agent_folder
    end

    # Returns whether this is the home folder rather than a project.
    def global?
      targets.global?
    end

    def initialize(root:, targets:, lock:, limits:)
      @root = root
      @targets = targets
      @lock = lock
      @limits = limits
    end

    # Returns +path+ as people read it: relative to the project, or from +~+.
    def display(path)
      targets.display(path)
    end

    # Returns how the lockfile records +source+: +owner/repo+, or a path
    # starting with +./+, +../+, +~/+, or +/+.
    def source_label(source)
      return source.name if source.github?

      path = display(source.path)
      path.start_with?('/', '~', '.') ? path : "./#{path}"
    end

    # Returns the Source a lockfile +entry+ came from.
    def source_of(entry)
      Source.parse(entry['source'], root: root, ref: entry['ref'])
    end

    # Returns the absolute target folders a lockfile +entry+ records,
    # without checking where they lead.
    def recorded_folders(entry)
      Array(entry['targets']).map { |path| targets.expand(path) }
    end

    # Returns the absolute target folders a lockfile +entry+ records. Raises
    # UnsafeError when one leads outside the project, or with +global+
    # outside the home folder.
    def folders(entry)
      recorded_folders(entry).each do |folder|
        next if targets.boundary.include?(folder)

        raise UnsafeError, "#{display(lock.path)} installs into #{display(folder)}, outside " \
                           "#{targets.boundary.name}. Fix or delete that entry"
      end
    end

    # Returns the target folders for +agents+ and +dirs+, or the detected
    # ones. Raises UnsafeError when one leads outside the project, or with
    # +global+ outside the home folder.
    def resolve(agents: [], dirs: [])
      targets.resolve(agents: agents, dirs: dirs).map(&:path).each do |folder|
        next if targets.boundary.include?(folder)

        raise UnsafeError, "#{display(folder)} leads outside #{targets.boundary.name}. Skills install only inside it"
      end
    end

    # Returns whether the skill folder at +path+ still holds what +entry+
    # recorded.
    def unchanged?(path, entry)
      return false unless entry && File.directory?(path)

      Tree.read(path, limits: @limits).digest(executable: entry['executable'] ? true : false) == entry['digest']
    rescue UnsafeError
      false
    end

    # Raises ConflictError when the skill +name+ in +folder+ was edited
    # since it was installed, unless +force+.
    def ensure_unedited(name, folder, force)
      destination = Installer.destination(folder, name)
      return if !File.exist?(destination) || force || unchanged?(destination, lock[name])

      raise ConflictError, "#{display(destination)} was edited since it was installed. Pass --force to replace it"
    end

    # Raises ConflictError when installing +name+ into +folder+ would
    # replace something this command did not install, or edited since.
    def ensure_replaceable(name, folder, force)
      destination = Installer.destination(folder, name)
      return if force || !(File.exist?(destination) || File.symlink?(destination))

      entry = lock[name]
      unless entry && folders(entry).include?(File.expand_path(folder))
        raise ConflictError, "#{display(destination)} exists and was not installed by skill. Pass --force to replace it"
      end

      ensure_unedited(name, folder, false)
    end

    # Returns the state of an installed skill: ok, edited, missing, partly
    # missing, or outside the project (or home folder) when the lockfile
    # points elsewhere.
    def status(name, entry)
      boundary = targets.boundary
      return "outside #{boundary.name}" unless recorded_folders(entry).all? { |folder| boundary.include?(folder) }

      paths = folders(entry).map { |folder| Installer.destination(folder, name) }
      present = paths.select { |path| File.directory?(path) }
      return 'missing' if present.empty?
      return 'partly missing' if present.size < paths.size

      paths.all? { |path| unchanged?(path, entry) } ? 'ok' : 'edited'
    end

    # Returns one line saying where a lockfile +entry+ came from.
    def self.describe(entry)
      text = entry['source'].dup
      text << "##{entry['ref']}" if entry['ref']
      text << " (#{entry['ref_type']} at #{entry['commit'][0, 12]})" if entry['commit']
      text
    end
  end
end
