# frozen_string_literal: true

module Skill
  # Where skills come from, parsed from what follows +skill add+:
  #
  #   owner/repo                         every skill in the repository
  #   owner/repo@pdf                     one skill, by name
  #   owner/repo/skills/pdf              one folder of the repository
  #   owner/repo#v1.2.0                  a branch, tag, or commit
  #   owner/repo#v1.2.0@pdf              both
  #   https://github.com/owner/repo/tree/main/skills/pdf
  #   ./path/to/skills                   a local directory
  class Source
    OWNER = /\A[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})\z/
    REPO = /\A[A-Za-z0-9._-]{1,100}\z/
    REF = %r{\A(?!-)(?!.*\.\.)(?!.*//)[A-Za-z0-9._/+-]{1,250}(?<![./])\z}
    GITHUB_URL = %r{\Ahttps?://(?:www\.)?github\.com/([^/]+)/([^/#?]+?)(?:\.git)?(?:/tree/([^/]+)(?:/(.+?))?)?/?\z}

    attr_reader :kind, :owner, :repo, :ref, :subpath, :skills, :path

    class << self
      # Returns the Source +input+ names, relative paths read from +root+.
      def parse(input, root: Dir.pwd, ref: nil)
        text = input.to_s.strip
        raise UsageError, 'Name a source, such as owner/repo or ./path' if text.empty?
        return local(text, root) if local?(text)

        text = text.delete_prefix('github:')
        text, fragment = text.split('#', 2)
        fragment_ref, fragment_skill = fragment.to_s.split('@', 2)
        github(text, ref: ref || presence(fragment_ref), skill: presence(fragment_skill))
      end

      # Returns whether +text+ reads as a local path.
      def local?(text)
        text.start_with?('./', '../', '/', '~/', '.\\', '..\\') || %w[. .. ~].include?(text) ||
          text.match?(%r{\A[A-Za-z]:[\\/]})
      end

      # Returns a relative path inside a repository, without empty or +.+
      # segments. Raises UnsafeError for absolute paths and +..+.
      def clean_path(path)
        text = path.to_s.tr('\\', '/')
        if text.start_with?('/') || text.match?(/\A[A-Za-z]:/)
          raise UnsafeError,
                "#{path.inspect} is not a relative path"
        end

        parts = text.split('/').reject { |part| part.empty? || part == '.' }
        raise UnsafeError, "#{path.inspect} leaves its folder" if parts.include?('..') || text.include?("\0")

        parts.join('/')
      end

      private

      def presence(value)
        value unless value.nil? || value.empty?
      end

      def local(text, root)
        expanded = File.expand_path(text, root)
        new(kind: :local, path: expanded)
      end

      def github(text, ref:, skill:)
        if (match = GITHUB_URL.match(text))
          owner, repo, tree_ref, subpath = match.captures
          return build(owner, repo, ref: ref || tree_ref, subpath: subpath, skill: skill)
        end
        raise UsageError, "#{text.inspect} is not a GitHub repository like owner/repo" if text.include?(':')

        shorthand(text, ref: ref, skill: skill)
      end

      def shorthand(text, ref:, skill:)
        name, at_skill = text.split('@', 2)
        owner, repo, *rest = name.split('/')
        raise UsageError, "#{text.inspect} is not a GitHub repository like owner/repo" unless owner && repo

        build(owner, repo, ref: ref, subpath: rest.join('/'), skill: skill || presence(at_skill))
      end

      def build(owner, repo, ref:, subpath:, skill:)
        unless owner.match?(OWNER) && repo.match?(REPO) && !%w[. ..].include?(repo)
          raise UsageError, "#{owner}/#{repo} is not a GitHub repository name"
        end
        raise UsageError, "#{ref.inspect} is not a valid git ref" if ref && !ref.match?(REF)

        skills = skill.to_s.split(',').map(&:strip).reject(&:empty?)
        new(kind: :github, owner: owner, repo: repo.delete_suffix('.git'), ref: ref,
            subpath: clean_path(subpath.to_s), skills: skills)
      end
    end

    def initialize(kind:, owner: nil, repo: nil, ref: nil, subpath: '', skills: [], path: nil)
      @kind = kind
      @owner = owner
      @repo = repo
      @ref = ref
      @subpath = subpath.to_s
      @skills = skills.freeze
      @path = path
      freeze
    end

    def github?
      kind == :github
    end

    def local?
      kind == :local
    end

    # Returns the repository as +owner/repo+, or the local path.
    def name
      github? ? "#{owner}/#{repo}" : path
    end

    # Returns the repository's web address, or +nil+ for a local directory.
    def url
      "https://github.com/#{owner}/#{repo}" if github?
    end

    # Returns a copy with another ref.
    def with_ref(ref)
      self.class.new(kind: kind, owner: owner, repo: repo, ref: ref, subpath: subpath, skills: skills, path: path)
    end

    def to_s
      text = name
      text += "/#{subpath}" if github? && !subpath.empty?
      text += "##{ref}" if ref
      text
    end
  end
end
