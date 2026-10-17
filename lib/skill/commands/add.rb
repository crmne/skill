# frozen_string_literal: true

module Skill
  module Commands
    # skill add <source>: installs skills from a repository or folder.
    class Add < Command
      def run
        arguments = parse('add <source> [options]') { |opts| define(opts) }
        raise UsageError, "Name one source.\n\n#{usage}" unless arguments.size == 1

        source = Source.parse(arguments.first, root: session.cwd, ref: options[:ref])
        checkout = session.fetcher.checkout(source)
        discovery = Discovery.new(checkout.root, subpath: source.subpath, full_depth: options[:full_depth])
        discovery.warnings.each { |warning| warn(warning) }
        return list(checkout, discovery) if options[:list]

        install(checkout, Selection.new(session, checkout, discovery, options).skills)
      end

      private

      def define(opts)
        options.merge!(skills: [], plugins: [])
        opts.on('-s', '--skill NAME', 'Install this skill (repeatable, comma-separated, * for all)') do |value|
          options[:skills].concat(split(value))
        end
        opts.on('--plugin NAME', 'Install the skills of this marketplace plugin') do |value|
          options[:plugins].concat(split(value))
        end
        opts.on('--all', 'Install every valid skill the source holds') { options[:all] = true }
        opts.on('-l', '--list', 'List the skills the source holds, without installing') { options[:list] = true }
        opts.on('--ref REF', 'Branch, tag, or full commit SHA to install from') { |value| options[:ref] = value }
        opts.on('-x', '--keep-executable', 'Keep executable bits on scripts') { options[:executable] = true }
        opts.on('-f', '--force', 'Replace skills this command did not install, or that were edited') do
          options[:force] = true
        end
        opts.on('--full-depth', 'Also search the whole repository, beyond the usual folders') do
          options[:full_depth] = true
        end
      end

      def install(checkout, candidates)
        copies = candidates.map { |candidate| copy(checkout, candidate) }
        executable = options[:executable] ? true : false
        warn_executables(copies) unless executable
        Installer.new.install(copies)
        copies.each { |copy| workspace.lock[copy.name] = copy.entry }
        workspace.lock.save
        copies.each { |copy| say "Installed #{copy.name} into #{copy.labels.join(', ')}" }
        say "Recorded in #{workspace.display(workspace.lock.path)}."
      end

      def copy(checkout, candidate)
        refuse_links(checkout, candidate)
        name = candidate.manifest.name
        tree = Tree.read(candidate.path, limits: session.limits)
        folders = folders_for(name, checkout, candidate)
        folders.each { |folder| workspace.ensure_replaceable(name, folder, options[:force]) }
        Installer::Copy.new(name: name, tree: tree, targets: folders, executable: options[:executable] ? true : false,
                            entry: entry(checkout, candidate, tree, folders),
                            labels: folders.map { |folder| workspace.display(File.join(folder, name)) })
      end

      # Returns the folders to install into: those asked for, plus those an
      # earlier install from the same source recorded, so they stay alike.
      def folders_for(name, checkout, candidate)
        existing = workspace.lock[name]
        same = existing && existing['source'] == workspace.source_label(checkout.source)
        if existing && !(same && existing['path'] == candidate.relative) && !options[:force]
          raise ConflictError,
                "#{name} is installed from #{Workspace.describe(existing)}. Remove it first, or pass --force"
        end

        kept = same ? workspace.folders(existing) : []
        (kept + workspace.resolve(agents: options[:agents], dirs: options[:dirs])).uniq
      end

      def refuse_links(checkout, candidate)
        return unless checkout.link_inside?(candidate.relative)

        raise UnsafeError, "#{candidate.relative} holds a symbolic link; skills may not hold links"
      end

      def entry(checkout, candidate, tree, folders)
        executable = options[:executable] ? true : false
        resolution = checkout.resolution
        {
          'source' => workspace.source_label(checkout.source),
          'ref' => resolution&.name,
          'ref_type' => resolution ? resolution.type.to_s : 'local',
          'commit' => checkout.commit,
          'path' => candidate.relative,
          'plugin' => candidate.plugin,
          'digest' => tree.digest(executable: executable),
          'executable' => executable,
          'targets' => folders.map { |folder| workspace.display(folder) }
        }
      end

      def warn_executables(copies)
        copies.each do |copy|
          files = copy.tree.executables
          next if files.empty?

          warn("#{copy.name} has executable files, installed without the executable bit: #{files.join(', ')}. " \
               'Pass --keep-executable to keep it')
        end
      end

      def list(checkout, discovery)
        say "#{checkout.source}#{" at #{checkout.commit[0, 12]}" if checkout.commit}:"
        say '  (no skills)' if discovery.candidates.empty?
        discovery.candidates.each do |candidate|
          plugin = candidate.plugin ? " [#{candidate.plugin}]" : ''
          detail = candidate.valid? ? truncate(candidate.manifest.description) : "INVALID: #{candidate.error}"
          say "  #{candidate.name}#{plugin}  #{detail}"
        end
        discovery.external.each do |plugin|
          say "  [#{plugin['plugin']}] lives in #{plugin['source']}: run `skill add #{plugin['source']}`"
        end
        0
      end

      def truncate(text, length = 90)
        line = text.to_s.gsub(/\s+/, ' ')
        line.length > length ? "#{line[0, length - 1]}…" : line
      end
    end
  end
end
