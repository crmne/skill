# frozen_string_literal: true

require 'fileutils'
require 'json'

module Skill
  # +skills.lock+: what each installed skill came from, so +update+ can
  # fetch it again and +remove+ knows what it owns. Entries are sorted by
  # name and carry no timestamps, so two branches adding different skills
  # merge cleanly. A project's lockfile sits at its root, to be committed;
  # the global one in +$XDG_STATE_HOME/skill+ (+~/.local/state/skill+).
  #
  #   {
  #     "version": 1,
  #     "skills": {
  #       "pdf": {
  #         "source": "anthropics/skills",
  #         "ref": null,
  #         "ref_type": "branch",
  #         "commit": "dbd4588f9e1033efb41dad4bef2f7947c8993d44",
  #         "path": "skills/pdf",
  #         "plugin": "document-skills",
  #         "digest": "sha256-...",
  #         "executable": false,
  #         "targets": [".claude/skills", "app/skills"]
  #       }
  #     }
  #   }
  class Lockfile
    NAME = 'skills.lock'
    VERSION = 1
    KEYS = %w[source ref ref_type commit path plugin digest executable targets].freeze

    attr_reader :path, :skills

    # Returns the global lockfile's path.
    def self.global_path(env:, home:)
      state = env['XDG_STATE_HOME'].to_s.strip
      File.join(state.empty? ? File.join(home, '.local/state') : state, 'skill', NAME)
    end

    def initialize(path)
      @path = path
      @skills = File.exist?(path) ? parse(File.read(path, encoding: 'UTF-8')) : {}
    end

    def [](name)
      skills[name]
    end

    def include?(name)
      skills.key?(name)
    end

    def names
      skills.keys
    end

    # Records +entry+, a Hash with the keys of KEYS, for the skill +name+.
    def []=(name, entry)
      clean = entry.transform_keys(&:to_s).slice(*KEYS)
      clean['targets'] = Array(clean['targets']).uniq.sort
      clean.delete('plugin') if clean['plugin'].nil?
      skills[name] = clean
    end

    def delete(name)
      skills.delete(name)
    end

    # Writes the lockfile, or deletes it when it records nothing.
    def save
      if skills.empty?
        FileUtils.rm_f(path)
        return
      end

      FileUtils.mkdir_p(File.dirname(path))
      sorted = skills.sort.to_h { |name, entry| [name, ordered(entry)] }
      temporary = "#{path}.#{Process.pid}.tmp"
      File.write(temporary, "#{JSON.pretty_generate('version' => VERSION, 'skills' => sorted)}\n")
      File.rename(temporary, path)
    ensure
      FileUtils.rm_f(temporary) if temporary
    end

    private

    def ordered(entry)
      KEYS.select { |key| entry.key?(key) }.to_h { |key| [key, entry[key]] }
    end

    def parse(text)
      data = JSON.parse(text)
      unless data.is_a?(Hash) && data['skills'].is_a?(Hash)
        raise Error, "#{path} is not a skills lockfile. Fix or delete it"
      end
      raise Error, "#{path} was written by a newer skill. Run `gem update skill`" if data['version'].to_i > VERSION

      data['skills'].each do |name, entry|
        raise Error, "#{path} records an invalid skill name, #{name.inspect}" unless Manifest.valid_name?(name)
        unless entry.is_a?(Hash) && entry['source'].is_a?(String)
          raise Error,
                "#{path} records #{name} without a source"
        end
      end
      data['skills']
    rescue JSON::ParserError
      raise Error, "#{path} is not valid JSON. Resolve any merge conflict in it, or delete it and add the skills again"
    end
  end
end
