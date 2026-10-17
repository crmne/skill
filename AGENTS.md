# AGENTS.md

How the `skill` gem is built. For coding agents first, humans welcome.

## What this is

`skill` is a command line, run with `gem exec skill`, that installs [Agent Skills](https://agentskills.io/specification) (folders holding a `SKILL.md`) from GitHub repositories, plugin marketplaces, and local folders into the folders RubyLLM and coding agents read them from. It is the Ruby counterpart of [vercel-labs/skills](https://github.com/vercel-labs/skills) (`npx skills`): same sources, same agent folders, same skills.sh directory, plus a lockfile that records commits and updates that show what changes before they apply.

Plain Ruby (>= 3.1), no runtime dependencies: Net::HTTP, `Gem::Package::TarReader`, Zlib, JSON, Psych, and OptionParser from the standard library.

## Layout

| Path | Responsibility |
| --- | --- |
| `exe/skill` | The executable `gem exec` runs |
| `lib/skill.rb` | The `Skill` module, its errors, and autoloads |
| `lib/skill/cli.rb` | Dispatches subcommands, maps errors to exit statuses (1 failure, 2 usage) |
| `lib/skill/commands/` | One class per subcommand (`Add`, `Update`, `Remove`, `List`, `Find`, `Agents`) and `Selection`, which picks the skills `add` installs |
| `lib/skill/session.rb` | One run: streams, environment, prompts, downloads, cleanup |
| `lib/skill/style.rb` | Color for a terminal, off for pipes, `NO_COLOR`, and `TERM=dumb` |
| `lib/skill/workspace.rb` | The project or home folder: its `Targets` and `Lockfile`, and the edited/not-ours checks |
| `lib/skill/source.rb` | Parses `owner/repo`, `owner/repo@skill`, `owner/repo/path`, `#ref`, GitHub URLs, local paths |
| `lib/skill/github.rb` | Resolves refs through git's smart HTTP advertisement and downloads commit tarballs, no API |
| `lib/skill/http.rb` | Net::HTTP with redirects, byte limits, HTTPS only, credentials only to their host |
| `lib/skill/archive.rb` | Safe tarball extraction |
| `lib/skill/discovery.rb` | Finds skills in a tree the way `npx skills` does, plus marketplace manifests |
| `lib/skill/manifest.rb` | `SKILL.md` validation, the same rules as `RubyLLM::Skill` |
| `lib/skill/tree.rb` | A skill folder's files, digest, and diff |
| `lib/skill/installer.rb` | Staged copies and atomic swaps |
| `lib/skill/agents.rb`, `targets.rb` | Where each agent reads skills, and which folders a command targets |
| `lib/skill/boundary.rb` | The folders a command may write into, checked with links and `..` resolved |
| `lib/skill/lockfile.rb` | `skills.lock` |
| `lib/skill/directory.rb` | skills.sh search |
| `test/` | Minitest. `FakeHTTP` and `FakeRepo` in `test/test_helper.rb` stand in for GitHub; no test touches the network |
| `packaging/release-notes/` | Hand-written release notes, one file per version |

## Rules

- **No runtime dependencies.** Anything the standard library does not do, the gem does not do. Adding a dependency is a maintainer decision.
- **Ruby 3.1.** No `Data`, no `it`, no syntax newer than 3.1. CI runs 3.1 through 4.0.
- **Fast start.** `skill --version` must not load more than `lib/skill.rb`, the version, and the CLI. Require heavy libraries (`net/http`, `rubygems/package`, `yaml`) only in the files that use them, and reach classes through `autoload`.
- **The network only in `add`, `update`, and `find`.** Nothing the gem installs downloads anything later, and the gem never runs code from a skill.
- **Never follow a moving ref silently.** `update` shows the commit range and the files that change, and applies only after `--yes` or a yes at a terminal. A commit pin never moves; a moved tag is called out.
- **Never overwrite what the gem does not own.** A folder not in the lockfile, or edited since it was installed (its digest differs), is replaced only with `--force`.
- **Refuse, do not repair.** An archive path that is absolute, holds `..`, or leaves its folder fails the whole download. Links are never written or followed, and a skill holding one is refused. Downloads, extraction, and each skill have size and file-count limits (`Skill::Limits`).
- **Project or global is decided, never asked.** Inside a project (`Workspace.project_root`: a lockfile, Gemfile, gems.rb, .git, or package.json, else an agent's folder or instructions, never the home folder) commands work on the project; outside one, globally. `--global` and `--project` override, and `add` says "(global)" when it went there. `npx skills` asks on a terminal instead.
- **Write only inside the boundary.** `add`, `update`, and `remove` touch folders inside the project, or when global inside the home folder and the global agent folders the environment names. Every target, from the lockfile, `--dir`, or detection, goes through `Boundary` (links and `..` resolved) and one outside fails the command before anything changes.
- **Executable bits are dropped** unless `--keep-executable`, with a warning naming the files.
- **Every install is atomic.** Copies are staged beside their targets and swapped in by rename once all are ready; a failure leaves the previous state.
- **Secrets stay secret.** `GITHUB_TOKEN`/`GH_TOKEN` go only to github.com, api.github.com, and codeload.github.com, never into output, errors, or the lockfile.
- **Stay compatible with `npx skills`.** Same source syntax, same agent folders (`lib/skill/agents.rb` follows its `src/agents.ts`), same discovery folders. When it adds an agent, add the row.

## Setup and commands

```bash
bundle install
bundle exec rake          # tests and RuboCop
bundle exec rake test
bundle exec rubocop
ruby exe/skill help       # run from the checkout
```

## Code style

- No implementation comments. A comment earns its place only by stating a constraint the code cannot show. Public classes and methods get a short RDoc comment in the Rails API voice ("Returns the ...").
- RuboCop runs in CI; do not disable cops inline.
- Plain commit messages: a subject of at most 60 characters, a body wrapped at 72 that says why. No "Generated with" footers, no Co-Authored-By tags.

## Docs

- Voice is Rails-guides style: second person, present tense, short sentences, examples first. No em dashes, no hype, no "simply".
- A user-visible change is not done until the README changes in the same commit.


## Working style

- Work on the default branch for maintainer-directed work. Do not create a
  branch or pull request for work done with the maintainer unless explicitly
  asked. Pull requests remain required for outside contributions.
- Keep history linear. Make one focused commit per topic, never create merge
  commits, update with fast-forward-only pulls, and rebase unpublished work
  when necessary.
- Create releases only from tags whose commits are reachable from the default
  branch. Never publish a release from an unmerged branch.
- Keep changes within the requested scope. Preserve existing behavior unless
  the task explicitly changes it.
- Add focused regression tests for changed behavior and update documentation
  when user-visible behavior, configuration, files, or network access changes.

## Reviews

- Prioritize correctness, regressions, security, product fit, and unnecessary
  dependencies. Green CI is necessary but is not proof of correctness.
- State the user-visible UI impact at the start of every review.
- For a user-visible interface change, require before-and-after screenshots at
  representative sizes and, where supported, light and dark themes, attached
  to the pull request rather than committed. Treat missing visual evidence as
  a review blocker.
- Never claim a platform or workflow was tested unless it was actually run.


<!-- github-automation: pull-requests -->
## Pull requests

This section is maintained account-wide by
[crmne/github-automation](https://github.com/crmne/github-automation) and is
replaced when that policy changes. Do not edit it here. If it does not fit this
repository, say so in a review or issue, and put repository-specific rules in a
separate section, which takes precedence.

Review evidence stays out of the repository. Before-and-after screenshots,
captures, comparison pages, recordings, and anything else made to show
reviewers a change go in the pull request description or its comments: attach
the files there, or link a page published elsewhere. Only media the project
itself uses, such as documentation figures, release-note images, and app
assets, belongs in the repository.

Dependencies come from their package registry, such as crates.io, RubyGems, or
npm, or from repositories the maintainer controls, under `github.com/crmne/`
or this repository's own organization. A git dependency, or a patch, override,
or replace entry, may point only at such a repository, and adding or changing
one needs the maintainer's explicit approval. Never point a dependency at a
contributor's fork or any other source the maintainer does not control. When a
dependency needs a fix, send it upstream and ask the maintainer to carry it in
a fork they control until a release includes it.

Reviewers treat either problem in a pull request as a blocker.
<!-- /github-automation: pull-requests -->


## Releasing this gem

1. Bump `Skill::VERSION` in `lib/skill/version.rb`.
2. Write `packaging/release-notes/vX.Y.Z.md`, add the version to `CHANGELOG.md`, and commit them with the version bump.
3. Tag `vX.Y.Z` on `main`, push the tag, and publish a GitHub release from it with `gh release create vX.Y.Z --verify-tag --notes-file packaging/release-notes/vX.Y.Z.md`.
4. Publishing the release runs `.github/workflows/release.yml`: it checks the tag, version, branch, and notes, runs the tests, builds the gem, and pushes it to RubyGems through trusted publishing (OIDC, the `rubygems` environment). No API key is stored.

<!-- github-automation: release-notes -->
## Releases

This section is maintained account-wide by
[crmne/github-automation](https://github.com/crmne/github-automation) and is
replaced when that policy changes. Do not edit it here. If it does not fit this
repository, say so in a review or issue, and put repository-specific release
steps in a separate section, which takes precedence.

Never use em dashes in new or edited user-facing writing, including release
titles, release notes, and agent responses. Use commas, colons, parentheses,
or full stops. Existing text does not need to change just to follow this.

The rest of this section applies only when this repository publishes GitHub
releases. If it has none, skip it, and do not add tags, release workflows, or
release-notes files just to follow it.

Do not cut a release for every fix. Work accumulates on the default branch
until there is something substantial to announce: a feature, or a batch of
fixes worth a changelog entry. The exception is a regression in something just
released, which goes out as soon as it is fixed.

Before writing release notes, read the previous two stable releases and match
their style. If there are fewer, read the most recent releases that exist,
including prereleases, and follow their format.

- Start with a short plain-language summary, followed by a download line when
  the project ships binaries.
- Include screenshots or short videos of the main user-visible changes.
  Capture only synthetic demo content, never real user data. Host the media
  where earlier releases do, such as release assets or files beside the notes.
- Use `New` and `Fixed` sections as applicable, and `Known limitations` when
  there are any. Lead each item with a bold user-facing result and credit who
  did what with issue or pull request numbers ("By @x; thanks @y"),
  acknowledging reporters separately from implementers.
- Include a `Thanks` section listing contributors and reporters, and end with
  `**Full changelog**:` and a link comparing the previous tag.
- Write about what changed for the user, not the commit history. Describe
  known limitations honestly.

Every release description is these hand-written notes, never a list generated
by GitHub, a changelog tool, or commit subjects. Commit the notes before
tagging, in the repository's existing release-notes location, or as
`packaging/release-notes/vX.Y.Z.md` when it has none. Any publishing path that
uses the committed file works, for example `softprops/action-gh-release` with
`body_path` and `generate_release_notes: false`, `gh release create
--notes-file`, GoReleaser's `--release-notes`, or `gh release edit
--notes-file` when another step creates the release.

If the release path still generates its notes, switching it to the committed
file is part of preparing the next release. Make a missing notes file stop the
release before any tag or release is created.

A release is not finished until every image, video, and download link in its
notes loads. Upload the release media right after the release is published and
before announcing it, then open the published release and check every image
and link.
<!-- /github-automation: release-notes -->
