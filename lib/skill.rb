# frozen_string_literal: true

require_relative 'skill/version'

# Installs Agent Skills, folders holding a +SKILL.md+, from GitHub
# repositories, plugin marketplaces, and local directories into the folders
# RubyLLM and coding agents read them from.
#
# The command line is the main interface:
#
#   gem exec skill add anthropics/skills@pdf
#
# Everything loads on first use, so the command starts fast.
module Skill
  # Raised for every problem the command reports to the person running it.
  class Error < StandardError; end

  # Raised when a command line is malformed.
  class UsageError < Error; end

  # Raised when a +SKILL.md+ breaks the Agent Skills specification.
  class InvalidSkillError < Error; end

  # Raised when a repository, ref, or skill does not exist.
  class NotFoundError < Error; end

  # Raised when an archive or a skill folder holds something unsafe: a path
  # leaving its folder, a link, or more data than the limits allow.
  class UnsafeError < Error; end

  # Raised when installing would overwrite something the command does not own.
  class ConflictError < Error; end

  # Raised when a download fails.
  class NetworkError < Error; end

  # Raised when a download is larger than its limit.
  class TooLargeError < NetworkError; end

  autoload :Agents, 'skill/agents'
  autoload :Archive, 'skill/archive'
  autoload :Boundary, 'skill/boundary'
  autoload :CLI, 'skill/cli'
  autoload :Commands, 'skill/commands'
  autoload :Directory, 'skill/directory'
  autoload :Discovery, 'skill/discovery'
  autoload :Fetcher, 'skill/fetcher'
  autoload :GitHub, 'skill/github'
  autoload :HTTP, 'skill/http'
  autoload :Installer, 'skill/installer'
  autoload :Limits, 'skill/limits'
  autoload :Lockfile, 'skill/lockfile'
  autoload :Manifest, 'skill/manifest'
  autoload :Session, 'skill/session'
  autoload :Source, 'skill/source'
  autoload :Style, 'skill/style'
  autoload :Targets, 'skill/targets'
  autoload :Tree, 'skill/tree'
  autoload :Workspace, 'skill/workspace'
end
