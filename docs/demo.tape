# The README's demo. To record it again from the repository root:
#
#   gem build skill.gemspec -o /tmp/skill.gem
#   SKILL_GEM=/tmp/skill.gem vhs docs/demo.tape
#
# It runs `gem exec skill` against GitHub and skills.sh in a throwaway
# home folder and gem path, first globally, then in a new Rails app. The
# hidden setup installs Rails and RubyLLM there and makes one app first,
# so the recorded `rails new` and `bundle add` are quick, and it removes
# RDoc's RubyGems plugin from that gem path, which would print an empty
# "Done installing documentation" line on every `gem exec`. Until skill
# is on RubyGems, `gem exec` installs the gem file SKILL_GEM names, copied
# into the folders the demo runs it in. It needs Geist Mono installed
# where fontconfig finds it.

Output docs/demo.gif

Set Shell "bash"
Set FontFamily "Geist Mono"
Set FontSize 20
Set LineHeight 1.2
Set Width 1200
Set Height 880
Set Padding 32
Set Framerate 24
Set TypingSpeed 45ms
Set CursorBlink false
Set WindowBar Colorful
Set WindowBarSize 40
Set BorderRadius 10
Set WaitPattern /›\s*$/
Set WaitTimeout 30s
Set Theme { "name": "Live Wire", "background": "#0b0b0c", "foreground": "#e7e7ea", "cursor": "#e7e7ea", "selection": "#2a2a2e", "black": "#0b0b0c", "red": "#ff6b6b", "green": "#5ee38a", "yellow": "#f5c451", "blue": "#6cb6ff", "magenta": "#c49bff", "cyan": "#5fd7d7", "white": "#c9c9cf", "brightBlack": "#6e6e76", "brightRed": "#ff8787", "brightGreen": "#8af0aa", "brightYellow": "#ffd77a", "brightBlue": "#94caff", "brightMagenta": "#d7b8ff", "brightCyan": "#87e8e8", "brightWhite": "#ffffff" }

Hide
Type `export PATH="$(ruby -e 'print RbConfig::CONFIG["bindir"]'):/usr/bin:/bin" HOME="$(mktemp -d)"` Enter
Type `export GEM_HOME="$HOME/.gem" GEM_PATH="$HOME/.gem" PATH="$HOME/.gem/bin:$PATH" PS1='\[\e[90m\]\w\[\e[0m\] \[\e[32m\]›\[\e[0m\] '` Enter
Type `gem install rails ruby_llm --no-document --silent && rm -f "$GEM_HOME/plugins/rdoc_plugin.rb"` Enter
Wait@300s
Type `(cd "$(mktemp -d)" && rails new warm --minimal --quiet && cd warm && bundle add ruby_llm --quiet)` Enter
Wait@300s
Type `mkdir -p ~/.claude ~/demo-app && cp "$SKILL_GEM" ~ && cp "$SKILL_GEM" ~/demo-app && cd ~ && clear` Enter
Wait
Show

Sleep 600ms
Type "gem exec skill find pdf --limit 3"
Sleep 400ms
Enter
Wait
Sleep 2.5s

Type "gem exec skill add anthropics/skills@pdf --global"
Sleep 400ms
Enter
Wait
Sleep 2.5s

Type "gem exec skill list --global"
Sleep 400ms
Enter
Wait
Sleep 2.5s

Ctrl+L
Sleep 300ms
Type "# Or in a Rails app that uses RubyLLM"
Sleep 300ms
Enter
Type "rails new demo-app --minimal --quiet"
Sleep 300ms
Enter
Wait
Sleep 600ms
Type "cd demo-app && bundle add ruby_llm"
Sleep 300ms
Enter
Wait
Sleep 1s

Type "gem exec skill add anthropics/skills@pdf"
Sleep 400ms
Enter
Wait
Sleep 2.5s

Type "gem exec skill list"
Sleep 400ms
Enter
Wait
Sleep 2.5s

Ctrl+L
Sleep 300ms
Type "cat skills.lock"
Sleep 400ms
Enter
Wait
Sleep 4s
