# frozen_string_literal: true

module Skill
  module Commands
    # skill find <query>: searches the skills.sh directory.
    class Find < Command
      def run
        options[:limit] = 20
        query = parse('find <query> [options]', scope: false) do |opts|
          opts.on('--owner OWNER', 'Only skills from this GitHub owner') { |value| options[:owner] = value }
          opts.on('--limit N', Integer, 'Show at most N results (default 20)') { |value| options[:limit] = value }
        end.join(' ').strip
        raise UsageError, "Name what to search for.\n\n#{usage}" if query.empty?

        owner = options[:owner]
        raise UsageError, "#{owner} is not a GitHub owner" if owner && !owner.match?(Source::OWNER)

        show(query, Directory.new(http: session.http, env: session.env)
                             .search(query, owner: options[:owner], limit: options[:limit]))
      end

      private

      def show(query, results)
        return say("No skills found for #{query.inspect}.") if results.empty?

        rows = results.map { |result| [result.name, result.source, installs(result.installs), result.command] }
        width, sources, counts = (0..2).map { |column| rows.map { |row| row[column].length }.max }
        rows.each do |name, source, count, command|
          line = "#{style.bold(name.ljust(width))}  #{style.dim(source.ljust(sources))}"
          line += "  #{style.dim(count.rjust(counts))}" unless count.empty?
          say line.rstrip
          say "#{' ' * width}  #{style.dim(command)}"
        end
        0
      end

      def installs(count)
        return '' unless count.positive?
        return "#{compact(count / 1_000_000.0)}M installs" if count >= 1_000_000
        return "#{compact(count / 1000.0)}K installs" if count >= 1000

        "#{count} install#{'s' unless count == 1}"
      end

      def compact(number)
        number.round(1).to_s.delete_suffix('.0')
      end
    end
  end
end
