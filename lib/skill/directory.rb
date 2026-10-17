# frozen_string_literal: true

require 'json'
require 'uri'

module Skill
  # Searches skills.sh, the directory of Agent Skills vercel-labs/skills
  # reads, through the same public search endpoint its CLI uses.
  # +SKILLS_API_URL+ points it at another server with that endpoint.
  class Directory
    Result = Struct.new(:name, :source, :installs, keyword_init: true) do
      # Returns the command that installs this skill.
      def command
        "skill add #{source}@#{name}"
      end
    end

    DEFAULT_URL = 'https://skills.sh'
    MAX_BYTES = 4 * 1024 * 1024
    CONTROL = /[\u0000-\u001f\u007f-\u009f​-‏‪-‮⁦-⁩]/

    def initialize(http: HTTP.new, env: ENV)
      @http = http
      @base = env['SKILLS_API_URL'].to_s.strip.empty? ? DEFAULT_URL : env['SKILLS_API_URL'].strip.chomp('/')
    end

    # Returns up to +limit+ Results for +query+, most installed first,
    # optionally only from repositories of +owner+.
    def search(query, owner: nil, limit: 20)
      params = { 'q' => query, 'limit' => limit.to_s }
      params['owner'] = owner if owner
      url = "#{@base}/api/search?#{URI.encode_www_form(params)}"
      response = @http.get(url, limit: MAX_BYTES, headers: { 'Accept' => 'application/json' })
      raise NetworkError, "#{URI(@base).host} answered #{response.status} to the search" unless response.status == 200

      results(JSON.parse(response.body.force_encoding(Encoding::UTF_8)))
    rescue JSON::ParserError
      raise NetworkError, "#{URI(@base).host} sent a search result that is not JSON"
    end

    private

    def results(data)
      skills = data.is_a?(Hash) && data['skills'].is_a?(Array) ? data['skills'] : []
      results = skills.grep(Hash).filter_map do |skill|
        name = clean(skill['skillId'] || skill['name'])
        source = clean(skill['source'])
        next unless Manifest.valid_name?(name) && source.match?(%r{\A[\w.-]+/[\w.-]+(?:/[\w./-]+)?\z})

        Result.new(name: name, source: source, installs: skill['installs'].to_i)
      end
      results.sort_by { |result| -result.installs }
    end

    def clean(value)
      value.to_s.scrub.gsub(CONTROL, '').strip
    end
  end
end
