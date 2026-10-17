# frozen_string_literal: true

require 'fileutils'
require 'rubygems/package'
require 'tempfile'
require 'zlib'

module Skill
  # Extracts a gzipped tarball of a repository, as GitHub serves it, into a
  # folder. Only regular files and folders are written. Links are never
  # written or followed: their paths are returned, so a skill holding one
  # can be refused. Any path that is absolute, holds +..+, or would leave
  # the folder fails the whole archive, as does going over the limits.
  class Archive
    Result = Struct.new(:commit, :links, keyword_init: true)

    FILE_TYPES = ['0', "\0", ''].freeze
    LINK_TYPES = %w[1 2].freeze

    def initialize(limits: Limits.new)
      @limits = limits
    end

    # Extracts the gzipped tarball at +path+ into the folder +into+, dropping
    # the top folder every GitHub archive has. Returns a Result with the
    # commit git recorded in the archive's pax header, if any.
    def extract(path, into)
      Tempfile.create(['skill', '.tar'], binmode: true) do |tar|
        gunzip(path, tar)
        tar.rewind
        read(tar, File.realpath(into))
      end
    end

    private

    def gunzip(path, tar)
      size = 0
      Zlib::GzipReader.open(path) do |gzip|
        while (chunk = gzip.read(1024 * 1024))
          size += chunk.bytesize
          if size > @limits.extract_bytes
            raise UnsafeError,
                  Limits.exceeded(:extract_bytes, "The archive expands to more than #{@limits.extract_bytes} bytes")
          end

          tar.write(chunk)
        end
      end
    rescue Zlib::Error
      raise UnsafeError, 'The download is not a gzip archive'
    end

    def read(tar, into)
      state = { commit: nil, links: [], files: 0, long_name: nil }
      Gem::Package::TarReader.new(tar).each { |entry| visit(entry, into, state) }
      Result.new(commit: state[:commit], links: state[:links].uniq.freeze)
    rescue Gem::Package::TarInvalidError, ArgumentError => e
      raise UnsafeError, "The download is not a valid tar archive (#{e.class})"
    end

    def visit(entry, into, state)
      type = entry.header.typeflag
      case type
      when 'g' then state[:commit] ||= pax(entry.read.to_s)['comment']&.then { |sha| sha[/\A\h{40}\z/] }
      when 'x' then state[:long_name] = pax(entry.read.to_s)['path']
      when 'L' then state[:long_name] = entry.read.to_s.delete("\0")
      else store(entry, type, into, state)
      end
    end

    def store(entry, type, into, state)
      name = state[:long_name] || entry.full_name
      state[:long_name] = nil
      parts = relative_parts(name)
      return if parts.empty?

      if FILE_TYPES.include?(type)
        state[:files] += 1
        if state[:files] > @limits.extract_files
          raise UnsafeError,
                Limits.exceeded(:extract_files, "The archive holds more than #{@limits.extract_files} files")
        end

        write(File.join(into, *parts), entry)
      elsif type == '5'
        directory(File.join(into, *parts))
      elsif LINK_TYPES.include?(type)
        state[:links] << parts.join('/')
      end
    end

    # Splits an archive path into the parts below the archive's top folder,
    # refusing anything that could land outside the extraction folder.
    def relative_parts(name)
      text = name.to_s.dup.force_encoding(Encoding::UTF_8)
      if !text.valid_encoding? || text.include?("\0") || text.include?('\\') || text.start_with?('/') ||
         text.match?(/\A[A-Za-z]:/)
        raise UnsafeError, "The archive holds an unsafe path, #{name.inspect}"
      end

      parts = text.split('/').reject { |part| part.empty? || part == '.' }
      raise UnsafeError, "The archive holds an unsafe path, #{name.inspect}" if parts.include?('..')

      parts.drop(1)
    end

    def write(path, entry)
      FileUtils.mkdir_p(File.dirname(path))
      raise UnsafeError, "The archive writes #{path} twice" if File.symlink?(path) || File.directory?(path)

      File.open(path, 'wb', 0o644) do |file|
        while (chunk = entry.read(1024 * 1024))
          file.write(chunk)
        end
      end
      File.chmod(entry.header.mode.to_i.anybits?(0o111) ? 0o755 : 0o644, path)
    rescue SystemCallError => e
      raise UnsafeError, "The archive could not be extracted: #{e.class}"
    end

    def directory(path)
      FileUtils.mkdir_p(path)
    rescue SystemCallError => e
      raise UnsafeError, "The archive could not be extracted: #{e.class}"
    end

    # Reads pax extended header records: "<length> <key>=<value>\n".
    def pax(data)
      records = {}
      data = data.dup.force_encoding(Encoding::BINARY)
      until data.empty?
        length = data[/\A\d+/].to_i
        break if length <= 0 || length > data.bytesize

        key, value = data.byteslice(0, length).sub(/\A\d+ /, '').chomp.split('=', 2)
        records[key] = value.to_s.force_encoding(Encoding::UTF_8) if key
        data = data.byteslice(length..)
      end
      records
    end
  end
end
