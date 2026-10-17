# frozen_string_literal: true

require 'optparse'

module Skill
  # The +skill+ command line.
  class CLI
    COMMANDS = {
      'add' => :Add, 'install' => :Add, 'a' => :Add, 'i' => :Add,
      'list' => :List, 'ls' => :List,
      'update' => :Update, 'upgrade' => :Update, 'up' => :Update,
      'remove' => :Remove, 'rm' => :Remove, 'uninstall' => :Remove,
      'find' => :Find, 'search' => :Find, 's' => :Find,
      'agents' => :Agents
    }.freeze

    USAGE = <<~TEXT
      Usage: skill <command> [options]

      Commands:
        add <source>       Install skills from GitHub or a local folder
        list               List installed skills
        update [names]     Update installed skills, showing what changes first
        remove <names>     Remove installed skills
        find <query>       Search the skills.sh directory
        agents             List the agents and folders skills install to

      Sources:
        owner/repo                 a repository (asks which skills when it holds several)
        owner/repo@pdf             one skill by name
        owner/repo/skills/pdf      one folder of a repository
        owner/repo#v1.2.0          a branch, tag, or full commit SHA
        https://github.com/owner/repo/tree/main/skills/pdf
        ./path/to/skills           a local folder

      Run `skill <command> --help` for a command's options.
    TEXT

    def self.start(argv)
      exit new(argv).run
    end

    def initialize(argv, out: $stdout, err: $stderr, input: $stdin, env: ENV, cwd: Dir.pwd, home: Dir.home,
                   http: nil)
      @argv = argv.dup
      @session = Session.new(out: out, err: err, input: input, env: env, cwd: cwd, home: home, http: http)
    end

    # Runs the command and returns its exit status: 0 on success, 1 when it
    # failed, 2 for a malformed command line.
    def run
      name = @argv.shift
      case name
      when nil, 'help', '-h', '--help' then help
      when 'version', '-v', '--version' then version
      else command(name).run
      end
    rescue OptionParser::ParseError, UsageError => e
      fail_with(e, 2)
    rescue Error => e
      fail_with(e, 1)
    rescue Interrupt
      130
    ensure
      @session.cleanup
    end

    private

    def command(name)
      constant = COMMANDS.fetch(name) { raise UsageError, "Unknown command #{name.inspect}. Run `skill help`" }
      Commands.const_get(constant).new(@session, @argv)
    end

    def help
      @session.say USAGE
      0
    end

    def version
      @session.say "skill #{VERSION}"
      0
    end

    def fail_with(error, status)
      @session.error(error.message)
      status
    end
  end
end
