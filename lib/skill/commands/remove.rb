# frozen_string_literal: true

module Skill
  module Commands
    # skill remove <names>: deletes skills this command installed, from
    # every folder it recorded, or only those +--agents+ and +--dir+ name.
    class Remove < Command
      def run
        names = parse('remove <names> [options]') do |opts|
          opts.on('--all', 'Remove every installed skill') { options[:all] = true }
          opts.on('-f', '--force', 'Remove skills that were edited since they were installed') do
            options[:force] = true
          end
        end
        names = workspace.lock.names if options[:all]
        raise UsageError, "Name the skills to remove, or pass --all.\n\n#{usage}" if names.empty?

        plan = names.to_h { |name| [name, folders(name)] }
        plan.each { |name, folders| remove(name, folders) }
        workspace.lock.save
        0
      end

      private

      # Returns the folders to remove +name+ from, after checking each still
      # holds what was installed.
      def folders(name)
        entry = workspace.lock[name]
        refuse_unknown(name) unless entry
        recorded = workspace.folders(entry)
        folders = chosen_folders ? recorded & chosen_folders : recorded
        folders.each { |folder| workspace.ensure_unedited(name, folder, options[:force]) }
        folders
      end

      def refuse_unknown(name)
        found = workspace.targets.existing.map { |target| Installer.destination(target.path, name) }
                         .find { |path| File.exist?(path) }
        raise NotFoundError, "#{name} is not installed" unless found

        raise ConflictError, "#{workspace.display(found)} was not installed by skill. Delete it yourself"
      end

      def remove(name, folders)
        entry = workspace.lock[name]
        Installer.new.remove(name, folders)
        remaining = entry['targets'].reject { |path| folders.include?(workspace.targets.expand(path)) }
        if remaining.empty?
          workspace.lock.delete(name)
        else
          workspace.lock[name] = entry.merge('targets' => remaining)
        end
        say done("Removed #{style.bold(name)} from " \
                 "#{folders.map { |folder| workspace.display(File.join(folder, name)) }.join(', ')}")
      end
    end
  end
end
