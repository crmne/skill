# frozen_string_literal: true

module Skill
  # Where a command works: a project (found from the current folder) or the
  # home folder, with its Targets and its Lockfile. Knows whether a folder
  # it would replace or delete is still what it installed.
  class Workspace
    ROOT_MARKERS = %w[skills.lock Gemfile gems.rb .git package.json].freeze

    attr_reader :root, :targets, :lock

    # Opens the project around +cwd+, or the home folder with +global+.
    def self.open(cwd:, home:, env:, global:, limits:)
      root = global ? home : project_root(cwd, home)
      lock = global ? Lockfile.global_path(env: env, home: home) : File.join(root, Lockfile::NAME)
      new(root: root, targets: Targets.new(root: root, home: home, env: env, global: global),
          lock: Lockfile.new(lock), limits: limits)
    end

    # Returns the nearest folder above +cwd+, up to +home+, holding a
    # lockfile, a Gemfile, a git repository, or a package.json, or +cwd+.
    def self.project_root(cwd, home)
      directory = cwd
      loop do
        return directory if ROOT_MARKERS.any? { |marker| File.exist?(File.join(directory, marker)) }

        parent = File.dirname(directory)
        return cwd if parent == directory || directory == home

        directory = parent
      end
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

    # Returns the absolute target folders a lockfile +entry+ records.
    def folders(entry)
      entry['targets'].map { |path| targets.expand(path) }
    end

    # Returns the target folders for +agents+ and +dirs+, or the detected ones.
    def resolve(agents: [], dirs: [])
      targets.resolve(agents: agents, dirs: dirs).map(&:path)
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

    # Returns the state of an installed skill: ok, edited, missing, or
    # partly missing.
    def status(name, entry)
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
