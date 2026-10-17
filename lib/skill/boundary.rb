# frozen_string_literal: true

module Skill
  # The folders a command may write skills into. A path is inside when,
  # with +..+ and symbolic links resolved, it lies in one of them, so a
  # lockfile or a link cannot lead an install or a removal elsewhere.
  class Boundary
    attr_reader :name

    # +folders+ are the folders allowed; +name+ says what they are, as
    # people read it ("the project").
    def initialize(folders, name:)
      @folders = folders.filter_map { |folder| self.class.real_path(File.expand_path(folder)) }.uniq
      @name = name
    end

    # Returns whether +path+ really lies inside one of the folders.
    def include?(path)
      real = self.class.real_path(File.expand_path(path))
      return false unless real

      @folders.any? { |folder| real == folder || real.start_with?("#{folder}/") }
    end

    # Returns +path+ with the deepest part that exists resolved and the
    # rest appended, or +nil+ when a link in it leads nowhere.
    def self.real_path(path)
      missing = []
      current = path
      until File.exist?(current) || File.symlink?(current)
        parent = File.dirname(current)
        return path if parent == current

        missing.unshift(File.basename(current))
        current = parent
      end
      File.join(File.realpath(current), *missing)
    rescue SystemCallError
      nil
    end
  end
end
