# frozen_string_literal: true

require 'test_helper'

class StyleTest < SkillTest
  def setup
    super
    repo = FakeRepo.new(@http, 'acme', 'skills')
    repo.commit({ 'skills/pdf/SKILL.md' => skill_md('pdf'), 'skills/pdf/run.py' => ['print(1)', 0o755] })
    File.write(File.join(@project, 'Gemfile'), "gem 'ruby_llm'\n")
    @http.route('https://skills.sh/api/search?q=pdf&limit=20',
                body: JSON.generate(skills: [{ skillId: 'pdf', source: 'acme/skills', installs: 1500 }]))
  end

  def terminal
    io = StringIO.new
    def io.tty? = true
    io
  end

  # Runs the command line with both streams on a terminal.
  def colored(*argv, env: {})
    out = terminal
    err = terminal
    status = Skill::CLI.new(argv, out: out, err: err, input: StringIO.new, env: env, cwd: @project, home: @home,
                                  http: @http).run
    [status, out.string, err.string]
  end

  def test_a_terminal_gets_color
    _status, out, err = colored('add', 'acme/skills@pdf')

    assert_equal "\e[32m✓\e[39m Installed \e[1mpdf\e[22m → app/skills/pdf\n\e[2m  Recorded in skills.lock\e[22m\n", out
    assert_equal "\e[33m! pdf: dropped the executable bit from 1 file (use --keep-executable)\e[39m\n", err

    _status, out, = colored('find', 'pdf')

    row = "\e[1mpdf\e[22m  \e[2macme/skills\e[22m  \e[2m1.5K installs\e[22m\n"

    assert_equal "#{row}     \e[2mskill add acme/skills@pdf\e[22m\n", out
  end

  def test_no_color_and_pipes_stay_plain
    _status, out, err = colored('add', 'acme/skills@pdf', env: { 'NO_COLOR' => '1' })

    assert_equal "✓ Installed pdf → app/skills/pdf\n  Recorded in skills.lock\n", out
    refute_includes err, "\e["

    _status, out, = skill('list')

    assert_equal "pdf  acme/skills  branch #{lock['pdf']['commit'][0, 12]}  app/skills\n", out
  end

  def test_dumb_terminals_stay_plain
    refute_predicate Skill::Style.for(terminal, { 'TERM' => 'dumb' }), :color?
    assert_predicate Skill::Style.for(terminal, {}), :color?
    refute_predicate Skill::Style.for(StringIO.new, {}), :color?
  end
end
