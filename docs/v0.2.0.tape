# The demo in the 0.2.0 release notes: agent groups and skill install.
# To record it again from the repository root:
#
#   gem build skill.gemspec -o /tmp/skill.gem
#   SKILL_GEM=/tmp/skill.gem gpu-lock vhs docs/v0.2.0.tape
#
# It installs the gem into a throwaway home folder and runs it against
# GitHub in a small project that uses RubyLLM and Claude Code. It needs
# Geist Mono installed where fontconfig finds it.

Output docs/v0.2.0.gif

Set Shell "bash"
Set FontFamily "Geist Mono"
Set FontSize 20
Set LineHeight 1.2
Set Width 1200
Set Height 720
Set Padding 32
Set Framerate 24
Set TypingSpeed 38ms
Set CursorBlink false
Set WindowBar Colorful
Set WindowBarSize 40
Set BorderRadius 10
Set WaitPattern /›\s*$/
Set WaitTimeout 30s
Set Theme { "name": "Live Wire", "background": "#0b0b0c", "foreground": "#e7e7ea", "cursor": "#e7e7ea", "selection": "#2a2a2e", "black": "#0b0b0c", "red": "#ff6b6b", "green": "#5ee38a", "yellow": "#f5c451", "blue": "#6cb6ff", "magenta": "#c49bff", "cyan": "#5fd7d7", "white": "#c9c9cf", "brightBlack": "#6e6e76", "brightRed": "#ff8787", "brightGreen": "#8af0aa", "brightYellow": "#ffd77a", "brightBlue": "#94caff", "brightMagenta": "#d7b8ff", "brightCyan": "#87e8e8", "brightWhite": "#ffffff" }

Hide
Type `exec env -i TERM="$TERM" LANG=C.UTF-8 SKILL_GEM="$SKILL_GEM" HOME="$(mktemp -d)" PATH="$(ruby -e 'print RbConfig::CONFIG["bindir"]'):/usr/bin:/bin" bash --noprofile --norc` Enter
Type `cd && export GEM_HOME="$HOME/.gem" GEM_PATH="$HOME/.gem" PATH="$HOME/.gem/bin:$PATH" PS1='\[\e[90m\]\w\[\e[0m\] \[\e[32m\]›\[\e[0m\] '` Enter
Type `gem install "$SKILL_GEM" --no-document --silent && mkdir -p demo-app/.claude && cd demo-app && git init -q && printf 'gem "ruby_llm"\n' > Gemfile && clear` Enter
Wait@120s
Show

Sleep 300ms
Type "skill add anthropics/skills@pdf --agents coding"
Sleep 400ms
Enter
Sleep 300ms
Hide
Wait
Show
Sleep 2s

Type "skill add anthropics/skills@xlsx --agents ruby_llm"
Sleep 400ms
Enter
Sleep 300ms
Hide
Wait
Show
Sleep 2s

Type "# A fresh clone: skills.lock, no skills"
Enter
Type "rm -rf .claude/skills app/skills"
Sleep 400ms
Enter
Sleep 300ms
Hide
Wait
Show
Sleep 600ms

Type "skill install"
Sleep 400ms
Enter
Sleep 300ms
Hide
Wait
Show
Sleep 2s

Type "skill install"
Sleep 400ms
Enter
Sleep 300ms
Hide
Wait
Show
Sleep 3s
