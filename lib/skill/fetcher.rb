# frozen_string_literal: true

require 'tmpdir'

module Skill
  # Gives a Source's files as a folder: a local directory in place, or a
  # GitHub commit downloaded and extracted into a temporary folder.
  class Fetcher
    # +root+ is the folder, +resolution+ a GitHub::Resolution (or +nil+ for a
    # local directory), and +links+ the archive paths that were links.
    Checkout = Struct.new(:source, :root, :resolution, :links, keyword_init: true) do
      def commit
        resolution&.commit
      end

      # Returns whether the archive held a link inside the folder +relative+.
      def link_inside?(relative)
        prefix = relative == '.' ? '' : "#{relative}/"
        links.any? { |link| link == relative || link.start_with?(prefix) }
      end
    end

    # Downloads go into folders under +workdir+, which the caller deletes.
    def initialize(github:, limits:, workdir:)
      @github = github
      @limits = limits
      @workdir = workdir
    end

    # Resolves +source+'s ref.
    def resolve(source)
      @github.resolve(source.owner, source.repo, source.ref)
    end

    # Returns a Checkout of +source+ at +resolution+ (resolved when +nil+).
    def checkout(source, resolution: nil)
      return local(source) if source.local?

      resolution ||= resolve(source)
      directory = Dir.mktmpdir('checkout-', @workdir)
      archive = File.join(directory, 'source.tar.gz')
      File.open(archive, 'wb') { |io| @github.download(source.owner, source.repo, resolution.commit, io) }
      root = File.join(directory, 'source')
      Dir.mkdir(root)
      result = Archive.new(limits: @limits).extract(archive, root)
      File.delete(archive)
      if result.commit && result.commit != resolution.commit
        raise NetworkError, "GitHub sent commit #{result.commit[0, 12]} for #{resolution.commit[0, 12]}"
      end

      Checkout.new(source: source, root: root, resolution: resolution, links: result.links)
    end

    private

    def local(source)
      raise NotFoundError, "No folder at #{source.path}" unless File.directory?(source.path)

      Checkout.new(source: source, root: File.realpath(source.path), resolution: nil, links: [])
    end
  end
end
