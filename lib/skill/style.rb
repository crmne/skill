# frozen_string_literal: true

module Skill
  # Colors text for a terminal. Off unless the stream is a terminal, and off
  # when +NO_COLOR+ is set or +TERM+ is +dumb+, so piped output stays plain.
  class Style
    CODES = { bold: [1, 22], dim: [2, 22], red: [31, 39], green: [32, 39], yellow: [33, 39] }.freeze

    # Returns a Style for +stream+, colored when it is a terminal and
    # +env+ allows it.
    def self.for(stream, env)
      terminal = stream.respond_to?(:tty?) && stream.tty?
      new(terminal && env['NO_COLOR'].to_s.empty? && env['TERM'] != 'dumb')
    end

    def initialize(color)
      @color = color
    end

    def color?
      @color
    end

    CODES.each do |name, (on, off)|
      define_method(name) { |text| @color ? "\e[#{on}m#{text}\e[#{off}m" : text.to_s }
    end
  end
end
