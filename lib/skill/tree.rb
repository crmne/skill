# frozen_string_literal: true

require 'digest'
require 'find'

module Skill
  # The files of one skill folder: their paths, contents' SHA-256, and
  # whether they are executable. Comparing two Trees shows what an update
  # changes; a Tree's digest shows whether an installed skill was edited.
  class Tree
    Entry = Struct.new(:sha256, :bytes, :executable, keyword_init: true)
    Diff = Struct.new(:added, :changed, :removed, keyword_init: true) do
      def empty?
        added.empty? && changed.empty? && removed.empty?
      end
    end

    attr_reader :root, :entries

    # Reads the folder at +root+. Raises UnsafeError when it holds a link,
    # anything other than files and folders, or more than +limits+ allow.
    def self.read(root, limits: Limits.new)
      new(root, scan(root.to_s, limits))
    end

    def self.scan(root, limits)
      raise UnsafeError, "#{root} is a link" if File.symlink?(root)

      entries = {}
      total = 0
      Find.find(root) do |path|
        next if path == root

        relative = path.delete_prefix("#{root}/")
        stat = File.lstat(path)
        raise UnsafeError, "#{relative} in #{File.basename(root)} is a link; skills may not hold links" if stat.symlink?
        next if stat.directory?
        raise UnsafeError, "#{relative} in #{File.basename(root)} is not a regular file" unless stat.file?

        total += stat.size
        too_large!(root, limits) if entries.size >= limits.skill_files || total > limits.skill_bytes

        entries[relative] = Entry.new(sha256: Digest::SHA256.file(path).hexdigest, bytes: stat.size,
                                      executable: stat.mode.anybits?(0o111)).freeze
      end
      entries.sort.to_h.freeze
    end

    def self.too_large!(root, limits)
      raise UnsafeError,
            "#{File.basename(root)} is larger than #{limits.skill_files} files or #{limits.skill_bytes} bytes. " \
            'Set SKILL_MAX_SKILL_FILES or SKILL_MAX_SKILL_BYTES higher for a source you trust'
    end
    private_class_method :scan, :too_large!

    def initialize(root, entries)
      @root = root.to_s
      @entries = entries
    end

    # Returns the digest of the files and their modes, as
    # "sha256-<hex>". +executable+ false ignores modes, for a copy that
    # dropped them.
    def digest(executable: true)
      lines = entries.map { |path, entry| "#{path}\0#{executable && entry.executable ? 'x' : '-'}\0#{entry.sha256}\n" }
      "sha256-#{Digest::SHA256.hexdigest(lines.join)}"
    end

    # Returns the paths of executable files.
    def executables
      entries.select { |_path, entry| entry.executable }.keys
    end

    # Returns the size of every file together.
    def bytes
      entries.values.sum(&:bytes)
    end

    # Returns what changes from +before+ to this Tree. Mode changes count
    # only when +executable+ is true.
    def diff_from(before, executable: true)
      old = before ? before.entries : {}
      changed = entries.select do |path, entry|
        previous = old[path]
        previous && (previous.sha256 != entry.sha256 || (executable && previous.executable != entry.executable))
      end
      Diff.new(added: (entries.keys - old.keys), changed: changed.keys, removed: (old.keys - entries.keys))
    end
  end
end
