# frozen_string_literal: true

module Skill
  module Commands
    # Which of a source's skills +skill add+ installs: the ones named after
    # +@+ or with +--skill+, a plugin's with +--plugin+, every valid one with
    # +--all+, or the only one there is. Anything else asks for a choice.
    class Selection
      def initialize(session, checkout, discovery, options)
        @session = session
        @source = checkout.source
        @candidates = discovery.candidates
        @external = discovery.external
        @names = @source.skills + options[:skills]
        @plugins = options[:plugins]
        @all = options[:all] || @names.include?('*')
      end

      # Returns the chosen Discovery::Candidates. Raises when a named skill
      # is missing or invalid, or when the choice is unclear.
      def skills
        raise NotFoundError, "#{@source} holds no skills#{external_hint}" if @candidates.empty?

        chosen = if @all then every
                 elsif @names.any? || @plugins.any? then named + plugins
                 else only
                 end
        chosen.uniq(&:relative)
      end

      private

      def every
        @candidates.reject(&:valid?).each do |candidate|
          @session.warn("Skipping #{candidate.relative}: #{candidate.error}")
        end
        chosen = @candidates.select(&:valid?).reject { |candidate| hidden?(candidate) }
        raise InvalidSkillError, "None of the skills in #{@source} is valid" if chosen.empty?

        chosen
      end

      def named
        @names.map do |name|
          candidate = @candidates.find { |each| each.name == name }
          raise NotFoundError, "No skill named #{name}. Skills: #{@candidates.map(&:name).join(', ')}" unless candidate
          raise InvalidSkillError, candidate.error unless candidate.valid?

          candidate
        end
      end

      def plugins
        @plugins.flat_map do |name|
          found = @candidates.select { |candidate| candidate.plugin == name && candidate.valid? }
          raise NotFoundError, "No plugin named #{name} with valid skills" if found.empty?

          found
        end
      end

      def only
        if @candidates.size == 1
          raise InvalidSkillError, @candidates.first.error unless @candidates.first.valid?

          return @candidates
        end

        raise UsageError, <<~TEXT.chomp
          #{@source} holds #{@candidates.size} skills: #{@candidates.map(&:name).join(', ')}
          Pick with #{@source.name}@NAME, --skill NAME, --plugin NAME, or --all. See them with --list.
        TEXT
      end

      def hidden?(candidate)
        candidate.manifest.internal? && !@session.internal_skills?
      end

      def external_hint
        return '' if @external.empty?

        sources = @external.map { |plugin| plugin['source'] }
        ". Its marketplace lists plugins from other repositories: #{sources.join(', ')}"
      end
    end
  end
end
