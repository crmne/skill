# frozen_string_literal: true

module Skill
  # What one run of the command shares: its streams, environment, folders,
  # and the downloads it made, which #cleanup deletes.
  class Session
    attr_reader :env, :cwd, :home

    def initialize(out:, err:, input:, env:, cwd:, home:, http: nil)
      @out = out
      @err = err
      @input = input
      @env = env
      @cwd = File.expand_path(cwd)
      @home = File.expand_path(home)
      @http = http
    end

    def say(text = '')
      @out.puts text
    end

    # Prints a warning on the error stream: "! " and +text+, yellow on a
    # terminal.
    def warn(text)
      @err.puts err_style.yellow("! #{text}")
    end

    def error(text)
      @err.puts "#{err_style.red('skill:')} #{text}"
    end

    # Returns the Style for standard output.
    def style
      @style ||= Style.for(@out, env)
    end

    # Returns the Style for the error stream.
    def err_style
      @err_style ||= Style.for(@err, env)
    end

    # Asks +question+ on a terminal. Returns +false+ without asking when
    # input is not a terminal.
    def confirm?(question)
      return false unless @input.respond_to?(:tty?) && @input.tty?

      @out.print "#{question} [y/N] "
      @out.flush
      @input.gets.to_s.strip.match?(/\Ay(?:es)?\z/i)
    end

    # Returns the Workspace for the project, or the home folder with +global+.
    def workspace(global: false)
      @workspace ||= Workspace.open(cwd: cwd, home: home, env: env, global: global, limits: limits)
    end

    def limits
      @limits ||= Limits.new(env)
    end

    def http
      @http ||= HTTP.new
    end

    def fetcher
      @fetcher ||= begin
        require 'tmpdir'
        @workdir = Dir.mktmpdir('skill-')
        Fetcher.new(github: GitHub.new(http: http, env: env, limits: limits), limits: limits, workdir: @workdir)
      end
    end

    # Returns whether internal skills may be installed without naming them.
    def internal_skills?
      %w[1 true].include?(env['INSTALL_INTERNAL_SKILLS'].to_s.downcase)
    end

    # Deletes everything downloaded during the run.
    def cleanup
      return unless @workdir

      require 'fileutils'
      FileUtils.rm_rf(@workdir)
    end
  end
end
