# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'skill'
require 'skill/cli'
require 'digest'
require 'fileutils'
require 'json'
require 'minitest/autorun'
require 'rubygems/package'
require 'stringio'
require 'tmpdir'
require 'zlib'

module SkillTestHelpers
  # Answers requests from a table of URLs, as Skill::HTTP would.
  class FakeHTTP
    attr_reader :requests

    def initialize
      @routes = {}
      @requests = []
    end

    def route(url, status: 200, body: '', headers: {})
      @routes[url] = Skill::HTTP::Response.new(status: status, body: body.b, headers: headers)
    end

    def get(url, limit:, headers: {}, io: nil)
      @requests << [url, headers]
      response = @routes.fetch(url) { Skill::HTTP::Response.new(status: 404, body: '', headers: {}) }
      raise Skill::TooLargeError, "more than #{limit} bytes" if response.body.bytesize > limit

      if io && response.status == 200
        io.write(response.body)
        return Skill::HTTP::Response.new(status: 200, body: nil, headers: response.headers)
      end
      response
    end
  end

  # A GitHub repository served through FakeHTTP: refs and commit archives.
  class FakeRepo
    attr_reader :owner, :repo, :branches, :tags

    def initialize(http, owner, repo)
      @http = http
      @owner = owner
      @repo = repo
      @branches = {}
      @tags = {}
      @head = 'main'
    end

    # Records a commit on +branch+ (default main) holding +files+, and
    # returns its SHA.
    def commit(files, branch: 'main', tag: nil, links: {})
      sha = Digest::SHA1.hexdigest("#{owner}/#{repo}#{files.inspect}#{links.inspect}#{rand}")
      @branches[branch] = sha if branch
      @tags[tag] = sha if tag
      archive = SkillTestHelpers.tarball("#{repo}-#{sha[0, 7]}", files, commit: sha, links: links)
      @http.route("https://codeload.github.com/#{owner}/#{repo}/tar.gz/#{sha}", body: archive)
      advertise
      sha
    end

    def advertise
      lines = []
      head = @branches[@head]
      lines << "#{head} HEAD\0multi_ack symref=HEAD:refs/heads/#{@head} agent=git/github\n" if head
      @branches.sort.each { |name, sha| lines << "#{sha} refs/heads/#{name}\n" }
      @tags.sort.each { |name, sha| lines << "#{sha} refs/tags/#{name}\n" }
      refs = lines.map { |line| SkillTestHelpers.pkt(line) }.join
      body = "#{SkillTestHelpers.pkt("# service=git-upload-pack\n")}0000#{refs}0000"
      @http.route("https://github.com/#{owner}/#{repo}.git/info/refs?service=git-upload-pack", body: body)
    end
  end

  module_function

  def pkt(line)
    format('%04x', line.bytesize + 4) + line
  end

  # Builds a gzipped tarball the way GitHub does: a pax global header
  # carrying the commit, then everything under one top folder.
  def tarball(top, files, commit: nil, links: {}, raw: [])
    tar = StringIO.new(+'')
    Gem::Package::TarWriter.new(tar) do |writer|
      raw_entry(tar, 'pax_global_header', pax('comment', commit), 'g') if commit
      writer.mkdir(top, 0o755)
      files.each do |path, content|
        mode = 0o644
        content, mode = content if content.is_a?(Array)
        writer.add_file_simple("#{top}/#{path}", mode, content.bytesize) { |io| io.write(content) }
      end
      links.each { |path, target| writer.add_symlink("#{top}/#{path}", target, 0o777) }
      raw.each { |name, content, type| raw_entry(tar, name, content, type) }
    end
    gzip(tar.string)
  end

  def gzip(data)
    io = StringIO.new(+'')
    writer = Zlib::GzipWriter.new(io)
    writer.write(data)
    writer.close
    io.string
  end

  def pax(key, value)
    record = " #{key}=#{value}\n"
    length = record.bytesize
    length += 1 until "#{length}#{record}".bytesize == length
    "#{length}#{record}"
  end

  # Writes a tar entry by hand, for types and names TarWriter refuses.
  def raw_entry(tar, name, content, type)
    header = Gem::Package::TarHeader.new(name: name, mode: 0o644, size: content.bytesize, typeflag: type,
                                         prefix: '', mtime: 0, uid: 0, gid: 0, uname: '', gname: '',
                                         linkname: '', devmajor: 0, devminor: 0)
    tar.write(header.to_s)
    tar.write(content)
    remainder = content.bytesize % 512
    tar.write("\0" * (512 - remainder)) unless remainder.zero?
  end

  def skill_md(name, description = "Does #{name} things. Use when #{name} is needed.", extra = '')
    "---\nname: #{name}\ndescription: #{description}\n#{extra}---\n\n# #{name}\n"
  end

  def write_tree(root, files)
    files.each do |path, content|
      mode = nil
      content, mode = content if content.is_a?(Array)
      full = File.join(root, path)
      FileUtils.mkdir_p(File.dirname(full))
      File.write(full, content)
      File.chmod(mode, full) if mode
    end
  end
end

class SkillTest < Minitest::Test
  include SkillTestHelpers

  def setup
    @tmp = Dir.mktmpdir('skill-test-')
    @project = File.join(@tmp, 'project')
    @home = File.join(@tmp, 'home')
    FileUtils.mkdir_p([@project, @home])
    @http = FakeHTTP.new
  end

  def teardown
    FileUtils.rm_rf(@tmp)
  end

  # Runs the command line in the project and returns [status, out, err].
  def skill(*argv, env: {}, input: StringIO.new, cwd: @project)
    out = StringIO.new
    err = StringIO.new
    status = Skill::CLI.new(argv, out: out, err: err, input: input, env: env, cwd: cwd, home: @home, http: @http).run
    [status, out.string, err.string]
  end

  def lock(root = @project)
    JSON.parse(File.read(File.join(root, 'skills.lock')))['skills']
  end
end
