# frozen_string_literal: true

require 'test_helper'

class GitHubTest < SkillTest
  def setup
    super
    @repo = FakeRepo.new(@http, 'acme', 'skills')
    @first = @repo.commit({ 'README.md' => 'one' }, tag: 'v1')
    @second = @repo.commit({ 'README.md' => 'two' })
    @repo.commit({ 'README.md' => 'dev' }, branch: 'dev')
  end

  def github(env = {})
    Skill::GitHub.new(http: @http, env: env, limits: Skill::Limits.new({}))
  end

  def test_default_branch
    resolution = github.resolve('acme', 'skills', nil)

    assert_equal [:branch, nil, @second, 'main'], resolution.to_a
    assert_equal 'main', resolution.label
  end

  def test_branches_tags_and_commits
    assert_equal :branch, github.resolve('acme', 'skills', 'dev').type
    assert_equal [:tag, 'v1', @first], github.resolve('acme', 'skills', 'v1').to_a.first(3)
    assert_predicate github.resolve('acme', 'skills', @first.upcase), :pinned?
  end

  def test_unknown_refs_and_short_shas
    assert_raises(Skill::NotFoundError) { github.resolve('acme', 'skills', 'nope') }
    error = assert_raises(Skill::NotFoundError) { github.resolve('acme', 'skills', @first[0, 7]) }
    assert_match(/full 40-character SHA/, error.message)
  end

  def test_missing_repository
    error = assert_raises(Skill::NotFoundError) { github.resolve('acme', 'missing', nil) }
    assert_match(/GITHUB_TOKEN/, error.message)
  end

  def test_token_goes_to_github_only_as_auth
    @http.route("https://api.github.com/repos/acme/skills/tarball/#{@first}", body: 'data')
    github('GITHUB_TOKEN' => 'secret').resolve('acme', 'skills', nil)
    github('GITHUB_TOKEN' => 'secret').download('acme', 'skills', @first, StringIO.new)

    refs_headers = @http.requests[0][1]

    assert_equal "Basic #{['x-access-token:secret'].pack('m0')}", refs_headers['Authorization']
    assert_equal 'Bearer secret', @http.requests[1][1]['Authorization']
  end

  def test_download_writes_the_archive
    io = StringIO.new(+'')
    github.download('acme', 'skills', @first, io)

    refute_empty io.string
    assert_raises(Skill::NotFoundError) { github.download('acme', 'skills', 'f' * 40, StringIO.new) }
  end
end
