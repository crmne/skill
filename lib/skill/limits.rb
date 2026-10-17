# frozen_string_literal: true

module Skill
  # How much the command downloads, extracts, and installs at most. Each
  # limit can be raised with an environment variable, for sources you trust.
  #
  # GitHub serves a whole commit as one archive and skills are found in it,
  # so the download and extraction limits fit popular repositories, whose
  # tests and recordings run to hundreds of megabytes. Both stream to disk,
  # never into memory. The per-skill limits stay tight, since only the
  # chosen skills' folders are installed.
  class Limits
    DEFAULTS = {
      download_bytes: ['SKILL_MAX_DOWNLOAD_BYTES', 512 * 1024 * 1024],
      extract_bytes: ['SKILL_MAX_EXTRACT_BYTES', 2 * 1024 * 1024 * 1024],
      extract_files: ['SKILL_MAX_EXTRACT_FILES', 100_000],
      skill_bytes: ['SKILL_MAX_SKILL_BYTES', 16 * 1024 * 1024],
      skill_files: ['SKILL_MAX_SKILL_FILES', 2_000]
    }.freeze

    attr_reader(*DEFAULTS.keys)

    # Returns +message+ followed by how to raise the +key+ limit, so a refusal
    # says what to do about it.
    def self.exceeded(key, message)
      "#{message}. Set #{DEFAULTS.fetch(key).first} higher for a source you trust"
    end

    def initialize(env = ENV, **overrides)
      DEFAULTS.each do |key, (variable, default)|
        value = overrides.fetch(key) { env[variable] ? Integer(env[variable], 10) : default }
        raise UsageError, "#{variable} must be a positive number" unless value.positive?

        instance_variable_set(:"@#{key}", value)
      end
    rescue ArgumentError
      raise UsageError, 'SKILL_MAX_* variables must be whole numbers of bytes or files'
    end
  end
end
