# frozen_string_literal: true

module Skill
  module Commands
    # skill agents: the targets skills install to.
    class Agents < Command
      def run
        parse('agents', scope: false)
        width = Skill::Agents.all.map { |agent| agent.key.length }.max
        Skill::Agents.all.each do |agent|
          global = agent.global_dir&.sub(/\A\{(\w+)\}/) { Skill::Agents::HOMES.fetch(Regexp.last_match(1)).last }
          global ||= '(project only)'
          say "#{agent.key.ljust(width)}  #{agent.project_dir.ljust(26)}  #{global.ljust(34)}  #{agent.name}"
        end
        0
      end
    end
  end
end
