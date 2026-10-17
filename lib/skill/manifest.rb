# frozen_string_literal: true

require 'date'
require 'yaml'

module Skill
  # A skill's +SKILL.md+, checked against the Agent Skills specification
  # (https://agentskills.io/specification) the way RubyLLM checks it: YAML
  # front matter with a +name+ of lowercase letters, digits, and single
  # hyphens, at most 64 characters, and a +description+ of at most 1,024.
  class Manifest
    FILE = 'SKILL.md'
    MAX_NAME = 64
    MAX_DESCRIPTION = 1024
    MAX_COMPATIBILITY = 500
    MAX_BYTES = 1024 * 1024
    FRONT_MATTER = /\A---[ \t]*\r?\n(.*?)^---[ \t]*(?:\r?\n|\z)/m
    NAME = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/

    attr_reader :name, :description, :metadata, :path

    # Reads the +SKILL.md+ in the folder at +path+. Raises InvalidSkillError
    # when it is missing or breaks the specification.
    def self.load(path)
      new(path)
    end

    # Returns whether +name+ is a valid skill name.
    def self.valid_name?(name)
      name.is_a?(String) && name.length <= MAX_NAME && name.match?(NAME)
    end

    def initialize(path)
      @path = path.to_s
      file = File.join(@path, FILE)
      invalid('is missing') unless File.file?(file) && !File.symlink?(file)
      invalid("is larger than #{MAX_BYTES} bytes") if File.size(file) > MAX_BYTES

      assign(front_matter(File.read(file, encoding: 'UTF-8')))
    end

    # Returns whether the front matter marks the skill internal, which hides
    # it unless it is asked for by name.
    def internal?
      %w[true 1 yes].include?(metadata['internal'].to_s.downcase)
    end

    private

    def front_matter(content)
      content = content.delete_prefix("\u{FEFF}")
      invalid('is not valid UTF-8') unless content.valid_encoding?
      match = FRONT_MATTER.match(content)
      invalid('must start with YAML front matter between --- lines') unless match

      data = YAML.safe_load(match[1], permitted_classes: [Date, Time], aliases: false)
      invalid('front matter must be a YAML mapping') unless data.is_a?(Hash)
      data.transform_keys(&:to_s)
    rescue Psych::Exception => e
      invalid("front matter is not valid YAML: #{e.message.lines.first.strip}")
    end

    def assign(data)
      @name = required(data, 'name', MAX_NAME)
      unless @name.match?(NAME)
        invalid("name #{@name.inspect} must be lowercase letters, digits, and single hyphens between them")
      end
      @description = required(data, 'description', MAX_DESCRIPTION)
      optional(data, 'license')
      optional(data, 'compatibility', MAX_COMPATIBILITY)
      optional(data, 'allowed-tools')
      @metadata = metadata_of(data['metadata'])
    end

    def required(data, key, limit)
      value = data[key]
      invalid("needs a #{key}") if value.nil? || (value.is_a?(String) && value.strip.empty?)

      optional(data, key, limit)
    end

    def optional(data, key, limit = nil)
      value = data[key]
      return if value.nil?

      invalid("#{key} must be a string") unless value.is_a?(String)
      invalid("#{key} must not be empty") if value.strip.empty?
      invalid("#{key} must be at most #{limit} characters") if limit && value.length > limit
      value.strip
    end

    def metadata_of(value)
      return {}.freeze if value.nil?

      invalid('metadata must be a mapping') unless value.is_a?(Hash)
      value.to_h { |key, entry| [key.to_s, entry.to_s] }.freeze
    end

    def invalid(reason)
      raise InvalidSkillError, "#{File.join(@path, FILE)} #{reason}"
    end
  end
end
