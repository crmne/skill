<div align="center">

# skill

<strong>Install Agent Skills into RubyLLM apps and coding agents, from Ruby</strong>

[![CI](https://github.com/crmne/skill/actions/workflows/ci.yml/badge.svg)](https://github.com/crmne/skill/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

<img src="docs/demo.gif" alt="gem exec skill finds the pdf skill on skills.sh, installs it into app/skills, lists it, shows skills.lock, and reports it up to date" width="800">

</div>

---

[Agent Skills](https://agentskills.io/specification) are folders of instructions, scripts, and reference files that teach a model a workflow. People publish them in GitHub repositories and plugin marketplaces. `skill` copies the ones you pick into the folder your app or agent reads them from, records where each came from, and shows you what changes before it updates them.

```sh
gem exec skill find pdf                    # search skills.sh
gem exec skill add anthropics/skills@pdf   # install one
```

```
✓ Installed pdf → app/skills/pdf, .claude/skills/pdf
  Recorded in skills.lock
```

It is the Ruby counterpart of [`npx skills`](https://github.com/vercel-labs/skills): the same sources, the same agent folders, the same [skills.sh](https://skills.sh) directory. [RubyLLM](https://rubyllm.com) is a first-class target, and it adds a lockfile with commits, updates that wait for your yes, and refusals instead of guesses. No runtime dependencies, Ruby 3.1 or newer, and it starts in about the time Ruby itself takes.

## Running it

With RubyGems 3.5 or newer (Ruby 3.3 ships it), run it without installing:

```sh
gem exec skill add owner/repo
```

`gem exec` asks RubyGems for the newest version on every run. Pass `--conservative` to use the version you already have, without the lookup:

```sh
gem exec --conservative skill list
```

Depending on your RDoc version, `gem exec` may print `Done installing documentation for  after 0 seconds` before the output, even when it installed nothing. That line comes from RDoc's RubyGems hook, not from `skill`, and is harmless.

Or install it once:

```sh
gem install skill
skill add owner/repo
```

In a Gemfile, add it with `require: false`, so it never loads into your app:

```ruby
gem "skill", require: false, group: :development
```

## Adding skills

Name a repository, and pick skills from it:

```sh
skill add anthropics/skills --list            # what it holds, installs nothing
skill add anthropics/skills@pdf               # one skill
skill add anthropics/skills@pdf,xlsx          # several
skill add anthropics/skills --skill pdf --skill docx
skill add anthropics/skills --plugin document-skills
skill add anthropics/skills --all             # every valid skill
```

A repository with one skill installs it directly. A repository with several asks you to pick: `skill` never installs a whole repository you did not ask for.

Sources:

| Source | Meaning |
| --- | --- |
| `owner/repo` | A GitHub repository, at its default branch |
| `owner/repo@pdf` | The skill named `pdf` in it |
| `owner/repo/skills/pdf` | One folder of it |
| `owner/repo#v1.2.0` | A branch, a tag, or a full 40-character commit SHA (also `--ref`) |
| `owner/repo#v1.2.0@pdf` | Both |
| `https://github.com/owner/repo/tree/main/skills/pdf` | A GitHub address |
| `./path/to/skills` | A folder on your computer |

`skill` finds skills where `npx skills` does: a `SKILL.md` at the top, `skills/` and the agents' own folders up to three levels deep, the plugins of a marketplace file (Claude Code's `.claude-plugin/marketplace.json`, Codex's `.agents/plugins/marketplace.json`, Cursor's `.cursor-plugin/marketplace.json`), and when those hold nothing, the whole repository. `--full-depth` searches the whole repository anyway.

Private repositories work with a token in `GITHUB_TOKEN` or `GH_TOKEN`.

## Where skills go

`skill` looks at your project and installs into every folder it shows signs of using:

| Target | `--agent` | Project folder | Global folder | Detected by |
| --- | --- | --- | --- | --- |
| RubyLLM | `rubyllm` | `app/skills` | none | `ruby_llm` in the Gemfile or lockfile, or an `app/skills` folder |
| Claude Code | `claude-code` | `.claude/skills` | `~/.claude/skills` | `.claude/` or `CLAUDE.md` |
| Codex | `codex` | `.agents/skills` | `~/.agents/skills` | `.codex/` or `AGENTS.md` |
| Cursor | `cursor` | `.agents/skills` | `~/.cursor/skills` | `.cursor/` or `.cursorrules` |
| Gemini CLI | `gemini-cli` | `.agents/skills` | `~/.gemini/skills` | `.gemini/` or `GEMINI.md` |
| GitHub Copilot | `github-copilot` | `.agents/skills` | `~/.copilot/skills` | `.github/copilot-instructions.md` |
| ...and 74 more | | | | their own folders |

When it finds none, it uses `.agents/skills`, the folder many agents share. `skill agents` lists all 80 targets. Folders several agents share get one copy.

Choose instead of detecting:

```sh
skill add anthropics/skills@pdf --agent rubyllm
skill add anthropics/skills@pdf --agent claude-code,cursor
skill add anthropics/skills@pdf --dir vendor/skills
```

`--global` (`-g`) installs into your home folder instead of the project, for the agents you have installed:

```sh
skill add anthropics/skills@pdf --global
```

Once installed in `app/skills`, RubyLLM finds a skill by name:

```ruby
chat = RubyLLM.chat.with_skills(:pdf)
```

## The lockfile

`skills.lock`, at the root of your project, records each skill's source, ref, commit, folder in the repository, the digest of its files, and where it is installed. Commit it with the skills.

```json
{
  "version": 1,
  "skills": {
    "pdf": {
      "source": "anthropics/skills",
      "ref": null,
      "ref_type": "branch",
      "commit": "dbd4588f9e1033efb41dad4bef2f7947c8993d44",
      "path": "skills/pdf",
      "plugin": "document-skills",
      "digest": "sha256-3a9465d4...",
      "executable": false,
      "targets": [".claude/skills", "app/skills"]
    }
  }
}
```

Entries are sorted and carry no timestamps, so two branches adding different skills merge cleanly. The global lockfile lives in `~/.local/state/skill/skills.lock` (or `$XDG_STATE_HOME/skill`).

## Updating

```sh
skill update            # every skill
skill update pdf        # one
skill update --dry-run  # only show what would change
skill update --yes      # apply without asking
```

`update` fetches each source again at the ref you installed:

* **A commit** never moves. The skill is skipped.
* **A tag** is checked again. If someone moved it, `update` says so before anything else.
* **A branch** moves forward. `update` shows the commit range, a compare link, and every file added, changed, or removed:

```
pdf: anthropics/skills dbd4588f9e10..5d6e7f8a9b0c
  https://github.com/anthropics/skills/compare/dbd4588f9e10...5d6e7f8a9b0c
  + scripts/merge.py
  ~ SKILL.md
Apply this update? [y/N]
```

Nothing changes until you answer yes, or pass `--yes`. Without a terminal and without `--yes`, `update` exits with status 1, so a scheduled job can tell you an update is waiting. When nothing moved, `update` makes one small request per repository and downloads nothing.

To move to another ref, add the skill again with it: `skill add anthropics/skills#v2@pdf`.

## Listing and removing

```sh
skill list              # installed skills, and any that were edited or are missing
skill list --json
skill remove pdf        # from every folder it was installed into
skill remove pdf --agent claude-code
```

`list` also names skill folders `skill` did not install. `remove` deletes only what `skill` installed.

## Finding skills

`find` searches [skills.sh](https://skills.sh), the directory `npx skills` uses:

```sh
skill find rails
```

```
rails-expert                jeffallan/claude-skills  4.6K installs
                            skill add jeffallan/claude-skills@rails-expert
```

`--owner` keeps one GitHub owner's skills.

## Safety

A skill's instructions steer a model and its scripts run with whatever your sandbox grants, so review a skill like any code you add. `skill` keeps the copying itself safe:

* **Every `SKILL.md` is checked** against the [specification](https://agentskills.io/specification) with the same rules as RubyLLM: front matter with a `name` of lowercase letters, digits, and single hyphens, at most 64 characters, and a `description` of at most 1,024. Invalid skills are listed and never installed.
* **Archives are extracted defensively.** A path that is absolute, holds `..`, or leaves its folder fails the whole download. Links are never written or followed, and a skill holding one is refused.
* **Sizes are capped:** 64 MB downloaded, 256 MB and 20,000 files extracted, 16 MB and 2,000 files per skill. Raise them for sources you trust with `SKILL_MAX_DOWNLOAD_BYTES`, `SKILL_MAX_EXTRACT_BYTES`, `SKILL_MAX_EXTRACT_FILES`, `SKILL_MAX_SKILL_BYTES`, and `SKILL_MAX_SKILL_FILES`.
* **Executable bits are dropped,** with a warning naming the files, unless you pass `--keep-executable`. RubyLLM runs a skill's scripts through an interpreter, so they need none.
* **Installs are atomic.** Copies are built beside their folders and swapped in once all are ready. A failure leaves everything as it was.
* **Skills stay where they belong.** `add`, `update`, and `remove` write only inside the project, or with `--global` inside your home folder (and any agent folder you moved elsewhere with its environment variable). Folders are checked with `..` and symbolic links resolved, so a `skills.lock` entry, a `--dir`, or a linked folder that leads elsewhere is refused with an error naming it, and nothing changes.
* **Your edits are yours.** A skill edited since it was installed, or a folder `skill` did not install, is replaced or removed only with `--force`.
* **No downloads at run time.** `skill` reaches the network only in `add`, `update`, and `find`. What it installs is plain files in your project.
* **GitHub without its API.** Refs come from git's own HTTP endpoint and files from one archive of the exact commit, so there is no rate limit and no git needed. A token, when set, goes only to GitHub.

## Environment

| Variable | Use |
| --- | --- |
| `GITHUB_TOKEN`, `GH_TOKEN` | Read private repositories |
| `XDG_CONFIG_HOME`, `CLAUDE_CONFIG_DIR`, `CODEX_HOME` | Where agents keep their global folders |
| `XDG_STATE_HOME` | Where the global lockfile lives |
| `INSTALL_INTERNAL_SKILLS` | Include skills whose front matter sets `metadata.internal: true` in `--all` |
| `SKILLS_API_URL` | Another server with the skills.sh search endpoint |
| `SKILL_MAX_*` | The limits above |
| `NO_COLOR` | Plain output on a terminal too. Output that is not a terminal is always plain |

## Compared with `npx skills`

| | `npx skills` | `skill` |
| --- | --- | --- |
| Runs with | Node.js | Ruby 3.1+, no dependencies |
| RubyLLM `app/skills` | No | Detected and first |
| Lockfile | Folder hash, no commit | Source, ref, commit, digest, folders |
| Updating | Installs the new version | Shows the commits and files, waits for yes; commits never move, moved tags are called out |
| Installs | Symlinks to one copy, or copies | Copies, swapped in atomically |
| Hosts | GitHub, GitLab, any git, well-known URLs | GitHub and local folders |

The agent folders and discovery rules follow [vercel-labs/skills](https://github.com/vercel-labs/skills) (MIT), so both tools install a skill to the same place.

## Development

```sh
bundle install
bundle exec rake    # tests and RuboCop
```

The tests never touch the network: a fake GitHub serves refs and archives built in the tests.

## License

MIT. See [LICENSE](LICENSE).
