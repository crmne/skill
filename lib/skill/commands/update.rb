# frozen_string_literal: true

module Skill
  module Commands
    # skill update [names]: fetches each skill's source again at the ref it
    # was installed from. A commit never moves. A tag is fetched again and a
    # tag that moved is called out. A branch moves forward. Nothing changes
    # before the changes are shown and confirmed, with a prompt on a
    # terminal or +--yes+ elsewhere.
    class Update < Command
      # One skill's update: the lockfile entry it will have, the copy to
      # install, and the files that change.
      Change = Struct.new(:name, :entry, :copy, :diff, :from, :to, :source, keyword_init: true)

      NO_DIFF = Tree::Diff.new(added: [].freeze, changed: [].freeze, removed: [].freeze).freeze

      def run
        names = parse('update [names] [options]') { |opts| define(opts) }
        lock = workspace.lock
        names = lock.names if names.empty?
        unknown = names - lock.names
        raise NotFoundError, "Not installed: #{unknown.join(', ')}. Run `skill list`" if unknown.any?
        return say('No skills installed.') if names.empty?

        changes = names.group_by { |name| lock[name].values_at('source', 'ref', 'ref_type') }.flat_map do |key, group|
          plan(*key, group)
        end
        apply(changes)
      end

      private

      def define(opts)
        opts.on('-n', '--dry-run', 'Show what would change, without changing anything') { options[:dry_run] = true }
        opts.on('-y', '--yes', 'Apply the changes without asking') { options[:yes] = true }
        opts.on('-f', '--force', 'Replace skills that were edited since they were installed') do
          options[:force] = true
        end
      end

      # Returns the Changes for the skills +names+, which share a source and
      # a ref, fetching the source only when its ref moved.
      def plan(source_label, ref, ref_type, names)
        lock = workspace.lock
        return pinned(names) if ref_type == 'commit'

        source = Source.parse(source_label, root: workspace.root, ref: ref)
        resolution = session.fetcher.resolve(source) if source.github?
        if resolution && names.all? { |name| lock[name]['commit'] == resolution.commit }
          names.each { |name| say "#{name}: up to date (#{resolution.label} at #{resolution.commit[0, 12]})" }
          return []
        end

        checkout = session.fetcher.checkout(source, resolution: resolution)
        warn_moved_tag(names, checkout) if ref_type == 'tag'
        names.filter_map { |name| change(checkout, name) }
      end

      def pinned(names)
        names.each { |name| say "#{name}: pinned to #{workspace.lock[name]['commit'][0, 12]}, skipped" }
        []
      end

      def warn_moved_tag(names, checkout)
        before = workspace.lock[names.first]['commit']
        return if before == checkout.commit

        warn("#{names.join(', ')}: the tag #{checkout.resolution.label} moved from #{before.to_s[0, 12]} " \
             "to #{checkout.commit[0, 12]}")
      end

      def change(checkout, name)
        entry = workspace.lock[name]
        candidate = find(checkout, name, entry)
        return unless candidate

        tree = Tree.read(candidate.path, limits: session.limits)
        folders = workspace.folders(entry)
        folders.each { |folder| workspace.ensure_unedited(name, folder, options[:force]) }
        updated = updated_entry(entry, checkout, tree)
        Change.new(name: name, entry: updated, diff: diff(name, folders, tree, updated), from: entry['commit'],
                   to: checkout.commit, source: checkout.source,
                   copy: Installer::Copy.new(name: name, tree: tree, targets: folders, entry: updated,
                                             executable: updated['executable'] ? true : false))
      end

      def find(checkout, name, entry)
        candidate = Discovery.new(checkout.root, subpath: entry['path']).candidates
                             .find { |each| each.relative == entry['path'] }
        if candidate&.valid? && candidate.name == name
          return candidate unless checkout.link_inside?(candidate.relative)

          raise UnsafeError, "#{candidate.relative} holds a symbolic link; skills may not hold links"
        end

        reason = candidate ? candidate.error || "it is now named #{candidate.name}" : "#{entry['path']} is gone"
        warn("#{name}: cannot update, #{reason}. Run `skill add` again to choose what to install")
        nil
      end

      def updated_entry(entry, checkout, tree)
        entry.merge('commit' => checkout.commit,
                    'ref_type' => checkout.resolution ? checkout.resolution.type.to_s : 'local',
                    'digest' => tree.digest(executable: entry['executable'] ? true : false))
      end

      # Returns what changes from the first installed copy that differs
      # from +tree+, or nothing when every copy already matches it.
      def diff(name, folders, tree, entry)
        executable = entry['executable'] ? true : false
        folders.each do |folder|
          path = Installer.destination(folder, name)
          return tree.diff_from(nil) unless File.directory?(path)

          installed = Tree.read(path, limits: session.limits)
          unless installed.digest(executable: executable) == entry['digest']
            return tree.diff_from(installed,
                                  executable: executable)
          end
        end
        NO_DIFF
      end

      def apply(changes)
        return say('Nothing to update.') if changes.empty?

        changes.each { |change| show(change) }
        return 0 if options[:dry_run]

        changed = changes.reject { |change| change.diff.empty? }
        return refuse if changed.any? && !confirmed?(changed.size)

        Installer.new.install(changed.map(&:copy))
        changes.each { |change| workspace.lock[change.name] = change.entry }
        workspace.lock.save
        say "Updated #{changes.map(&:name).join(', ')}."
      end

      def confirmed?(count)
        options[:yes] || session.confirm?(count == 1 ? 'Apply this update?' : "Apply these #{count} updates?")
      end

      def refuse
        session.error('Nothing changed. Run `skill update --yes` to apply.')
        1
      end

      def show(change)
        range = [change.from, change.to].compact.map { |sha| sha[0, 12] }.join('..')
        say "#{change.name}: #{change.source}#{" #{range}" unless range.empty?}"
        say "  #{compare_url(change)}" if compare_url(change)
        return say('  no file changes') if change.diff.empty?

        change.diff.added.each { |path| say "  + #{path}" }
        change.diff.changed.each { |path| say "  ~ #{path}" }
        change.diff.removed.each { |path| say "  - #{path}" }
      end

      def compare_url(change)
        source = change.source
        return unless source.github? && change.from && change.to && change.from != change.to

        GitHub.compare_url(source.owner, source.repo, change.from, change.to)
      end
    end
  end
end
