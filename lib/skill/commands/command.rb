# frozen_string_literal: true

require 'optparse'

module Skill
  module Commands
    # A subcommand: parses its options, then #run returns the exit status.
    class Command
      def initialize(session, argv)
        @session = session
        @argv = argv
        @options = { agents: [], dirs: [] }
      end

      private

      attr_reader :session, :options

      # Parses the arguments with the options +define+ adds, plus the scope
      # options (+--global+, +--project+, +--agents+, +--dir+) unless +scope+
      # is false, or only +--global+ and +--project+ when it is +:place+.
      # Returns the arguments left.
      def parse(banner, scope: true, &define)
        @parser = OptionParser.new do |opts|
          opts.banner = "Usage: skill #{banner}"
          scope_options(opts, targets: scope != :place) if scope
          define&.call(opts)
        end
        @parser.parse(@argv)
      end

      def usage
        @parser.to_s
      end

      def scope_options(opts, targets: true)
        opts.on('-g', '--global', 'Use the home folder, even inside a project') { options[:global] = true }
        opts.on('-p', '--project', 'Use the current folder as a project, even outside one') do
          options[:global] = false
        end
        return unless targets

        opts.on('-a', '--agents NAMES', '--agent NAMES',
                'Target these agents (comma-separated, repeatable): all (detected, the default),',
                'coding (detected coding agents, not RubyLLM), or names from `skill agents`') do |value|
          options[:agents].concat(split(value))
        end
        opts.on('-d', '--dir PATH', 'Target this folder (repeatable)') do |value|
          options[:dirs] << File.expand_path(value, session.cwd)
        end
      end

      def workspace
        session.workspace(global: options[:global])
      end

      # Returns the target folders the scope options name, or +nil+ when
      # they name none.
      def chosen_folders
        return if options[:agents].empty? && options[:dirs].empty?

        workspace.resolve(agents: options[:agents], dirs: options[:dirs])
      end

      def style
        session.style
      end

      # Returns "✓ " and +text+, the check green on a terminal.
      def done(text)
        "#{style.green('✓')} #{text}"
      end

      def say(text = '')
        session.say(text)
        0
      end

      def warn(text)
        session.warn(text)
      end

      def split(value)
        value.split(',').map(&:strip).reject(&:empty?)
      end
    end
  end
end
