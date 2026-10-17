# frozen_string_literal: true

require 'fileutils'
require 'securerandom'

module Skill
  # Copies skill folders into target folders. Each copy is built beside its
  # target, under a hidden name, and swapped in with renames once every copy
  # of every skill is ready, so a failure leaves the installed skills as
  # they were.
  class Installer
    # One skill to copy: the name it installs as, its Tree, the folders it
    # goes into, and whether its files keep their executable bits. +entry+
    # and +labels+ are for the caller's bookkeeping.
    Copy = Struct.new(:name, :tree, :targets, :executable, :entry, :labels, keyword_init: true)

    # Installs every Copy in +copies+ into each of its target folders.
    def install(copies)
      staged = {}
      copies.each do |copy|
        copy.targets.each do |target|
          FileUtils.mkdir_p(target)
          staging = hidden(target, copy.name)
          staged[staging] = destination(target, copy.name)
          stage(copy, staging)
        end
      end
      swapped = {}
      staged.each { |staging, final| swapped[final] = swap(staging, final) }
      swapped.each_value { |backup| FileUtils.rm_rf(backup) if backup }
    rescue StandardError
      swapped&.reverse_each { |final, backup| restore(final, backup) }
      staged&.each_key { |staging| FileUtils.rm_rf(staging) }
      raise
    end

    # Deletes the skill +name+ from each folder in +targets+.
    def remove(name, targets)
      targets.each do |target|
        final = destination(target, name)
        next unless File.exist?(final) || File.symlink?(final)

        trash = hidden(target, "#{name}-removed")
        File.rename(final, trash)
        FileUtils.rm_rf(trash)
      end
    end

    # Returns the folder +name+ installs to inside +target+.
    def self.destination(target, name)
      raise UnsafeError, "#{name.inspect} is not a skill name" unless Manifest.valid_name?(name)

      File.join(File.expand_path(target), name)
    end

    private

    def destination(target, name)
      self.class.destination(target, name)
    end

    def stage(copy, staging)
      Dir.mkdir(staging, 0o755)
      copy.tree.entries.each do |relative, entry|
        source = File.join(copy.tree.root, relative)
        file = File.join(staging, relative)
        FileUtils.mkdir_p(File.dirname(file))
        FileUtils.cp(source, file)
        File.chmod(copy.executable && entry.executable ? 0o755 : 0o644, file)
      end
    end

    def swap(staging, final)
      backup = nil
      if File.exist?(final) || File.symlink?(final)
        backup = hidden(File.dirname(final), "#{File.basename(final)}-previous")
        File.rename(final, backup)
      end
      File.rename(staging, final)
      backup
    end

    def restore(final, backup)
      FileUtils.rm_rf(final)
      File.rename(backup, final) if backup && File.exist?(backup)
    end

    def hidden(target, name)
      File.join(target, ".skill-#{name}-#{SecureRandom.hex(4)}")
    end
  end
end
