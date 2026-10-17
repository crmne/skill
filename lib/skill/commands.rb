# frozen_string_literal: true

module Skill
  # The subcommands of the command line, one class each.
  module Commands
    autoload :Add, 'skill/commands/add'
    autoload :Agents, 'skill/commands/agents'
    autoload :Command, 'skill/commands/command'
    autoload :Find, 'skill/commands/find'
    autoload :Install, 'skill/commands/install'
    autoload :List, 'skill/commands/list'
    autoload :Remove, 'skill/commands/remove'
    autoload :Selection, 'skill/commands/selection'
    autoload :Update, 'skill/commands/update'
  end
end
