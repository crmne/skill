# frozen_string_literal: true

module Skill
  # Reads GitHub repositories without the API and without git: refs come
  # from git's smart HTTP advertisement, files from one tarball of a commit.
  # Neither counts against the API's rate limit. +GITHUB_TOKEN+ or
  # +GH_TOKEN+, when set, opens private repositories.
  class GitHub
    # A ref resolved to a commit. +type+ is +:branch+, +:tag+, or +:commit+;
    # +name+ is +nil+ for the repository's default branch.
    Resolution = Struct.new(:type, :name, :commit, :branch, keyword_init: true) do
      def pinned?
        type == :commit
      end

      # Returns the ref as people read it: the tag, the branch, or the
      # default branch's name.
      def label
        name || branch || 'HEAD'
      end
    end

    SHA = /\A\h{40}\z/
    MAX_REFS_BYTES = 32 * 1024 * 1024

    def initialize(http: HTTP.new, env: ENV, limits: Limits.new(env))
      @http = http
      @token = [env['GITHUB_TOKEN'], env['GH_TOKEN']].map(&:to_s).find { |value| !value.strip.empty? }&.strip
      @limits = limits
    end

    # Resolves +ref+ (a branch, a tag, a full commit SHA, or +nil+ for the
    # default branch) in +owner/repo+. A tag wins over a branch of the same
    # name, as in git.
    def resolve(owner, repo, ref)
      return Resolution.new(type: :commit, name: ref.downcase, commit: ref.downcase) if ref&.match?(SHA)

      refs = advertised_refs(owner, repo)
      return default_branch(owner, repo, refs) if ref.nil?

      name = ref.delete_prefix('refs/heads/').delete_prefix('refs/tags/')
      if (commit = refs[:tags][name]) && !ref.start_with?('refs/heads/')
        Resolution.new(type: :tag, name: name, commit: commit)
      elsif (commit = refs[:branches][name])
        Resolution.new(type: :branch, name: name, commit: commit, branch: name)
      elsif ref.match?(/\A\h{4,39}\z/)
        raise NotFoundError,
              "#{ref} is not a branch or tag of #{owner}/#{repo}. Pin commits by their full 40-character SHA"
      else
        raise NotFoundError, "#{owner}/#{repo} has no branch or tag named #{ref}"
      end
    end

    # Downloads +commit+ of +owner/repo+ as a gzipped tarball into +io+.
    def download(owner, repo, commit, io)
      url, headers = archive_request(owner, repo, commit)
      response = download_archive(url, headers, io, owner, repo)
      return if response.status == 200

      if [404, 422].include?(response.status)
        raise NotFoundError, "#{owner}/#{repo} has no commit #{commit}#{private_hint}"
      end

      raise NetworkError, "GitHub answered #{response.status} for the archive of #{owner}/#{repo}"
    end

    # Returns a link comparing two commits, for showing what changed.
    def self.compare_url(owner, repo, from, to)
      "https://github.com/#{owner}/#{repo}/compare/#{from[0, 12]}...#{to[0, 12]}"
    end

    private

    def download_archive(url, headers, io, owner, repo)
      @http.get(url, headers: headers, limit: @limits.download_bytes, io: io)
    rescue TooLargeError
      message = "#{owner}/#{repo} is larger than #{@limits.download_bytes} bytes to download"
      raise TooLargeError, Limits.exceeded(:download_bytes, message)
    end

    def advertised_refs(owner, repo)
      response = @http.get("https://github.com/#{owner}/#{repo}.git/info/refs?service=git-upload-pack",
                           headers: basic_auth, limit: MAX_REFS_BYTES)
      if [401, 403, 404].include?(response.status)
        raise NotFoundError, "No GitHub repository #{owner}/#{repo}#{private_hint}"
      end
      raise NetworkError, "GitHub answered #{response.status} for #{owner}/#{repo}" unless response.status == 200

      parse_refs(response.body)
    end

    # Reads git's pkt-line ref advertisement: a service line, a flush, then
    # one "<sha> <ref>" line per ref, the first carrying capabilities after
    # a NUL byte. Peeled tags end in ^{}.
    def parse_refs(body)
      refs = { head: nil, symref: nil, branches: {}, tags: {} }
      pkt_lines(body).each do |line|
        line, capabilities = line.chomp.split("\0", 2)
        refs[:symref] ||= capabilities.to_s[%r{symref=HEAD:refs/heads/(\S+)}, 1]
        sha, name = line.split(' ', 2)
        next unless sha&.match?(SHA) && name

        add_ref(refs, sha, name)
      end
      refs
    end

    def add_ref(refs, sha, name)
      case name
      when 'HEAD' then refs[:head] = sha
      when %r{\Arefs/heads/(.+)\z} then refs[:branches][Regexp.last_match(1)] = sha
      when %r{\Arefs/tags/(.+)\^\{\}\z} then refs[:tags][Regexp.last_match(1)] = sha
      when %r{\Arefs/tags/(.+)\z} then refs[:tags][Regexp.last_match(1)] ||= sha
      end
    end

    def pkt_lines(body)
      lines = []
      position = 0
      while position + 4 <= body.bytesize
        length = Integer(body.byteslice(position, 4), 16)
        position += 4
        next if length.zero?
        raise NetworkError, 'GitHub sent a malformed ref list' if length < 4

        lines << body.byteslice(position, length - 4).force_encoding(Encoding::UTF_8).scrub
        position += length - 4
      end
      lines.reject { |line| line.start_with?('# service=') }
    rescue ArgumentError
      raise NetworkError, 'GitHub sent a malformed ref list'
    end

    def default_branch(owner, repo, refs)
      raise NotFoundError, "#{owner}/#{repo} is empty" unless refs[:head]

      branch = refs[:symref] || refs[:branches].key(refs[:head])
      Resolution.new(type: :branch, name: nil, commit: refs[:head], branch: branch)
    end

    def archive_request(owner, repo, commit)
      return ["https://codeload.github.com/#{owner}/#{repo}/tar.gz/#{commit}", {}] unless @token

      ["https://api.github.com/repos/#{owner}/#{repo}/tarball/#{commit}",
       { 'Authorization' => "Bearer #{@token}", 'Accept' => 'application/vnd.github+json' }]
    end

    def basic_auth
      return {} unless @token

      { 'Authorization' => "Basic #{["x-access-token:#{@token}"].pack('m0')}" }
    end

    def private_hint
      @token ? '' : ' (for a private repository, set GITHUB_TOKEN)'
    end
  end
end
