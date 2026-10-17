# frozen_string_literal: true

module Skill
  module Commands
    # skill install: installs what the lockfile records, each skill at its
    # recorded commit, into its recorded folders, the way +bundle install+
    # restores a Gemfile.lock. Skills already in place with the recorded
    # digest are left alone, and each copy fetched is checked against that
    # digest before it is written. Given a source, works as +skill add+.
    class Install < Command
      def run
        return Add.new(session, @argv).run if @argv.any? { |argument| !argument.start_with?('-') }

        names = parse('install [options]', scope: :place) do |opts|
          opts.on('-f', '--force', 'Replace skills that were edited since they were installed') do
            options[:force] = true
          end
        end
        raise UsageError, "skill install takes no names.\n\n#{usage}" unless names.empty?

        install
      end

      private

      def install
        lock = workspace.lock
        return say("No skills recorded in #{workspace.display(lock.path)}.") if lock.names.empty?

        missing = lock.names.to_h { |name| [name, missing_folders(name)] }.reject { |_name, folders| folders.empty? }
        (lock.names - missing.keys).each do |name|
          say "#{style.dim('·')} #{style.bold(name)} #{style.dim('already installed')}"
        end
        copies = missing.group_by { |name, _folders| lock[name].values_at('source', 'commit') }.values
        restore(copies.flat_map { |group| fetch(group) })
      end

      def restore(copies)
        return 0 if copies.empty?

        Installer.new.install(copies)
        copies.each { |copy| say done("Installed #{style.bold(copy.name)} → #{copy.labels.join(', ')}") }
        0
      end

      # Returns the recorded folders of +name+ that do not hold it as
      # recorded, after refusing any that hold an edited copy.
      def missing_folders(name)
        entry = workspace.lock[name]
        workspace.folders(entry).reject do |folder|
          path = Installer.destination(folder, name)
          next true if workspace.unchanged?(path, entry)

          workspace.ensure_replaceable(name, folder, options[:force])
          false
        end
      end

      # Returns the copies for +group+, pairs of a skill name and its
      # folders, which share a source and a commit.
      def fetch(group)
        entry = workspace.lock[group.first.first]
        checkout = session.fetcher.checkout(source(entry), resolution: resolution(entry))
        group.map { |name, folders| copy(checkout, name, folders) }
      end

      def source(entry)
        workspace.source_of(entry)
      end

      def resolution(entry)
        commit = entry['commit']
        return if commit.nil? || entry['ref_type'] == 'local'

        unless commit.match?(/\A\h{40}\z/)
          raise Error, "#{workspace.display(workspace.lock.path)} records an invalid commit for #{entry['source']}"
        end

        GitHub::Resolution.new(type: entry['ref_type'] == 'commit' ? :commit : entry['ref_type'].to_sym,
                               name: entry['ref'], commit: commit.downcase, branch: entry['ref'])
      end

      def copy(checkout, name, folders)
        entry = workspace.lock[name]
        path = File.join(checkout.root, entry['path'].to_s)
        raise NotFoundError, "#{name}: #{entry['path']} is gone from #{entry['source']}" unless File.directory?(path)
        if checkout.link_inside?(entry['path'])
          raise UnsafeError, "#{entry['path']} holds a symbolic link; skills may not hold links"
        end

        executable = entry['executable'] ? true : false
        tree = Tree.read(path, limits: session.limits)
        verify(name, entry, tree.digest(executable: executable))
        Installer::Copy.new(name: name, tree: tree, targets: folders, executable: executable, entry: entry,
                            labels: folders.map { |folder| workspace.display(File.join(folder, name)) })
      end

      def verify(name, entry, digest)
        return if digest == entry['digest']

        if entry['ref_type'] == 'local'
          raise ConflictError, "#{name}: #{entry['source']} changed since it was recorded. " \
                               'Run `skill update` to install what it holds now'
        end
        raise UnsafeError, "#{name}: #{entry['source']} at #{entry['commit'].to_s[0, 12]} does not match " \
                           "the digest #{workspace.display(workspace.lock.path)} records"
      end
    end
  end
end
