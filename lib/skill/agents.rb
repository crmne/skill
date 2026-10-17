# frozen_string_literal: true

module Skill
  # The places each target reads skills from, in a project and in the home
  # folder. RubyLLM comes first; the coding agents follow the table of
  # vercel-labs/skills (https://github.com/vercel-labs/skills), so both
  # tools install a skill to the same folder.
  module Agents
    Agent = Struct.new(:key, :name, :project_dir, :global_dir, keyword_init: true) do
      def global?
        !global_dir.nil?
      end
    end

    # A global folder may start with a placeholder for a folder an
    # environment variable can move: +{config}+ is +XDG_CONFIG_HOME+, and the
    # others are the agents' own variables, such as +CLAUDE_CONFIG_DIR+.
    HOMES = {
      'config' => ['XDG_CONFIG_HOME', '~/.config'],
      'claude' => ['CLAUDE_CONFIG_DIR', '~/.claude'],
      'autohand' => ['AUTOHAND_HOME', '~/.autohand'],
      'grok' => ['GROK_HOME', '~/.grok'],
      'hermes' => ['HERMES_HOME', '~/.hermes'],
      'vibe' => ['VIBE_HOME', '~/.vibe']
    }.freeze

    ROWS = [
      ['rubyllm', 'RubyLLM', 'app/skills', nil],
      ['aider-desk', 'AiderDesk', '.aider-desk/skills', '~/.aider-desk/skills'],
      ['amp', 'Amp', '.agents/skills', '{config}/agents/skills'],
      ['antigravity', 'Antigravity', '.agents/skills', '~/.gemini/antigravity/skills'],
      ['antigravity-cli', 'Antigravity CLI', '.agents/skills', '~/.gemini/antigravity-cli/skills'],
      ['astrbot', 'AstrBot', 'data/skills', '~/.astrbot/data/skills'],
      ['autohand-code', 'Autohand Code CLI', '.autohand/skills', '{autohand}/skills'],
      ['augment', 'Augment', '.augment/skills', '~/.augment/skills'],
      ['bob', 'IBM Bob', '.bob/skills', '~/.bob/skills'],
      ['claude-code', 'Claude Code', '.claude/skills', '{claude}/skills'],
      ['openclaw', 'OpenClaw', 'skills', '~/.openclaw/skills'],
      ['cline', 'Cline', '.agents/skills', '~/.agents/skills'],
      ['codearts-agent', 'CodeArts Agent', '.codeartsdoer/skills', '~/.codeartsdoer/skills'],
      ['codebuddy', 'CodeBuddy', '.codebuddy/skills', '~/.codebuddy/skills'],
      ['codemaker', 'Codemaker', '.codemaker/skills', '~/.codemaker/skills'],
      ['codestudio', 'Code Studio', '.codestudio/skills', '~/.codestudio/skills'],
      ['codex', 'Codex', '.agents/skills', '~/.agents/skills'],
      ['command-code', 'Command Code', '.commandcode/skills', '~/.commandcode/skills'],
      ['continue', 'Continue', '.continue/skills', '~/.continue/skills'],
      ['cortex', 'Cortex Code', '.cortex/skills', '~/.snowflake/cortex/skills'],
      ['crush', 'Crush', '.crush/skills', '~/.config/crush/skills'],
      ['cursor', 'Cursor', '.agents/skills', '~/.cursor/skills'],
      ['deepagents', 'Deep Agents', '.agents/skills', '~/.deepagents/agent/skills'],
      ['devin', 'Devin for Terminal', '.devin/skills', '{config}/devin/skills'],
      ['dexto', 'Dexto', '.agents/skills', '~/.agents/skills'],
      ['droid', 'Droid', '.agents/skills', '~/.factory/skills'],
      ['eve', 'Eve', 'agent/skills', nil],
      ['firebender', 'Firebender', '.agents/skills', '~/.firebender/skills'],
      ['forgecode', 'ForgeCode', '.forge/skills', '~/.forge/skills'],
      ['fx', 'fx', '.agents/skills', '~/.agents/skills'],
      ['gemini-cli', 'Gemini CLI', '.agents/skills', '~/.gemini/skills'],
      ['github-copilot', 'GitHub Copilot', '.agents/skills', '~/.copilot/skills'],
      ['goose', 'Goose', '.goose/skills', '{config}/goose/skills'],
      ['grok', 'Grok Build', '.grok/skills', '{grok}/skills'],
      ['hermes-agent', 'Hermes Agent', '.hermes/skills', '{hermes}/skills'],
      ['inference-sh', 'inference.sh', '.inferencesh/skills', '~/.inferencesh/skills'],
      ['jazz', 'Jazz', '.jazz/skills', '~/.jazz/skills'],
      ['junie', 'Junie', '.junie/skills', '~/.junie/skills'],
      ['iflow-cli', 'iFlow CLI', '.iflow/skills', '~/.iflow/skills'],
      ['kilo', 'Kilo Code', '.agents/skills', '~/.kilo/skills'],
      ['kimchi', 'Kimchi', '.kimchi/skills', '~/.config/kimchi/harness/skills'],
      ['kimi-code-cli', 'Kimi Code CLI', '.agents/skills', '~/.agents/skills'],
      ['kiro-cli', 'Kiro CLI', '.kiro/skills', '~/.kiro/skills'],
      ['kode', 'Kode', '.kode/skills', '~/.kode/skills'],
      ['lingma', 'Lingma', '.lingma/skills', '~/.lingma/skills'],
      ['loaf', 'Loaf', '.agents/skills', '~/.agents/skills'],
      ['mcpjam', 'MCPJam', '.mcpjam/skills', '~/.mcpjam/skills'],
      ['minimax-code', 'MiniMax Code', '.minimax/skills', '~/.minimax/skills'],
      ['mistral-vibe', 'Mistral Vibe', '.vibe/skills', '{vibe}/skills'],
      ['moxby', 'Moxby', '.moxby/skills', '~/.moxby/skills'],
      ['mux', 'Mux', '.mux/skills', '~/.mux/skills'],
      ['opencode', 'OpenCode', '.agents/skills', '{config}/opencode/skills'],
      ['openhands', 'OpenHands', '.openhands/skills', '~/.openhands/skills'],
      ['ona', 'Ona', '.ona/skills', '~/.ona/skills'],
      ['pi', 'Pi', '.agents/skills', '~/.agents/skills'],
      ['posit-assistant', 'Posit Assistant', '.posit/assistant/skills', '~/.posit/assistant/skills'],
      ['qoder', 'Qoder', '.qoder/skills', '~/.qoder/skills'],
      ['qoder-cn', 'Qoder CN', '.qoder/skills', '~/.qoder-cn/skills'],
      ['qwen-code', 'Qwen Code', '.qwen/skills', '~/.qwen/skills'],
      ['replit', 'Replit', '.agents/skills', '{config}/agents/skills'],
      ['reasonix', 'Reasonix', '.reasonix/skills', '~/.reasonix/skills'],
      ['rovodev', 'Rovo Dev', '.rovodev/skills', '~/.rovodev/skills'],
      ['roo', 'Roo Code', '.roo/skills', '~/.roo/skills'],
      ['sarvam-code', 'Sarvam Code', '.agents/skills', '~/.agents/skills'],
      ['tabnine-cli', 'Tabnine CLI', '.tabnine/agent/skills', '~/.tabnine/agent/skills'],
      ['terramind', 'Terramind', '.terramind/skills', '~/.terramind/skills'],
      ['tinycloud', 'Tinycloud', '.tinycloud/skills', '~/.tinycloud/skills'],
      ['trae', 'Trae', '.trae/skills', '~/.trae/skills'],
      ['trae-cn', 'Trae CN', '.trae/skills', '~/.trae-cn/skills'],
      ['warp', 'Warp', '.agents/skills', '~/.agents/skills'],
      ['windsurf', 'Windsurf', '.windsurf/skills', '~/.codeium/windsurf/skills'],
      ['zed', 'Zed', '.agents/skills', '~/.agents/skills'],
      ['zcode', 'ZCode', '.zcode/skills', '~/.zcode/skills'],
      ['zencoder', 'Zencoder', '.zencoder/skills', '~/.zencoder/skills'],
      ['zenflow', 'Zenflow', '.zencoder/skills', '~/.zencoder/skills'],
      ['neovate', 'Neovate', '.neovate/skills', '~/.neovate/skills'],
      ['pochi', 'Pochi', '.pochi/skills', '~/.pochi/skills'],
      ['promptscript', 'PromptScript', '.agents/skills', nil],
      ['adal', 'AdaL', '.adal/skills', '~/.adal/skills'],
      ['universal', 'Universal', '.agents/skills', '{config}/agents/skills']
    ].freeze

    ALIASES = {
      'ruby_llm' => 'rubyllm', 'ruby-llm' => 'rubyllm', 'rails' => 'rubyllm',
      'claude' => 'claude-code', 'copilot' => 'github-copilot', 'gemini' => 'gemini-cli'
    }.freeze

    ALL = ROWS.to_h do |key, name, project_dir, global_dir|
      [key, Agent.new(key: key, name: name, project_dir: project_dir, global_dir: global_dir).freeze]
    end.freeze

    class << self
      # Returns every Agent, RubyLLM first.
      def all
        ALL.values
      end

      # Returns the Agent called +key+ or one of its aliases. Raises
      # UsageError for an unknown name.
      def fetch(key)
        name = key.to_s.strip.downcase
        ALL.fetch(ALIASES.fetch(name, name)) do
          raise UsageError, "Unknown agent #{key.inspect}. Run `skill agents` for the list"
        end
      end

      # Returns the absolute global folder of +agent+, or +nil+ when it has
      # none, reading placeholders from +env+ and +~+ as +home+.
      def global_path(agent, env:, home:)
        return unless agent.global?

        path = agent.global_dir.sub(/\A\{(\w+)\}/) do
          variable, default = HOMES.fetch(Regexp.last_match(1))
          value = env[variable].to_s.strip
          value.empty? ? default : value
        end
        File.expand_path(path.sub(%r{\A~(?=/|\z)}, home))
      end
    end
  end
end
