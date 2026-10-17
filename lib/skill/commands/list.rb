# frozen_string_literal: true

module Skill
  module Commands
    # skill list: the skills in the lockfile, whether each is still as
    # installed, and the skill folders this command did not install.
    class List < Command
      def run
        parse('list [options]') { |opts| opts.on('--json', 'Print JSON') { options[:json] = true } }
        rows = workspace.lock.skills.map { |name, entry| [name, entry, workspace.status(name, entry)] }
        rows.select! { |_name, entry, _status| workspace.folders(entry).intersect?(chosen_folders) } if chosen_folders
        return json(rows) if options[:json]

        installed(rows)
        unmanaged
        0
      end

      private

      def installed(rows)
        return say("No skills installed with skill in #{workspace.display(workspace.root)}.") if rows.empty?

        width = rows.map { |name, _entry, _status| name.length }.max
        rows.each do |name, entry, state|
          say "#{name.ljust(width)}  #{Workspace.describe(entry)}#{"  (#{state})" unless state == 'ok'}"
          say "#{' ' * width}  in #{entry['targets'].join(', ')}"
        end
      end

      def unmanaged
        managed = workspace.lock.names
        folders = workspace.targets.existing.flat_map do |target|
          Dir.children(target.path).sort.filter_map do |child|
            path = File.join(target.path, child)
            next if child.start_with?('.') || managed.include?(child) || !File.file?(File.join(path, Manifest::FILE))

            workspace.display(path)
          end
        end
        return if folders.empty?

        say
        say 'Not installed by skill:'
        folders.each { |folder| say "  #{folder}" }
      end

      def json(rows)
        require 'json'
        say JSON.pretty_generate(rows.to_h { |name, entry, state| [name, entry.merge('status' => state)] })
      end
    end
  end
end
