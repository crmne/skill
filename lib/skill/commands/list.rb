# frozen_string_literal: true

module Skill
  module Commands
    # skill list: the skills in the lockfile, whether each is still as
    # installed, and the skill folders this command did not install.
    class List < Command
      def run
        parse('list [options]') { |opts| opts.on('--json', 'Print JSON') { options[:json] = true } }
        rows = workspace.lock.skills.map { |name, entry| [name, entry, workspace.status(name, entry)] }
        if chosen_folders
          rows.select! { |_name, entry, _status| workspace.recorded_folders(entry).intersect?(chosen_folders) }
        end
        return json(rows) if options[:json]

        installed(rows)
        unmanaged
        0
      end

      private

      def installed(rows)
        return say("No skills installed with skill in #{workspace.display(workspace.root)}.") if rows.empty?

        table = rows.map do |name, entry, state|
          [name, source(entry), version(entry), entry['targets'].join(', '), state == 'ok' ? '' : state]
        end
        widths = (0..3).map { |column| table.map { |row| row[column].length }.max }
        table.each { |row| say row_line(row, widths) }
      end

      def row_line(row, widths)
        name, source, version, targets, state = row.each_with_index.map do |cell, column|
          column < 4 && column != 3 ? cell.ljust(widths[column]) : cell
        end
        line = "#{style.bold(name)}  #{style.dim(source)}  #{style.dim(version)}  #{targets}"
        line += "  #{style.yellow(state)}" unless state.empty?
        line
      end

      def source(entry)
        entry['ref'] ? "#{entry['source']}##{entry['ref']}" : entry['source']
      end

      def version(entry)
        entry['commit'] ? "#{entry['ref_type']} #{entry['commit'][0, 12]}" : entry['ref_type'].to_s
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
        say style.dim('Not installed by skill:')
        folders.each { |folder| say "  #{folder}" }
      end

      def json(rows)
        require 'json'
        say JSON.pretty_generate(rows.to_h { |name, entry, state| [name, entry.merge('status' => state)] })
      end
    end
  end
end
