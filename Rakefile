# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rake/testtask'

Rake::TestTask.new(:test) do |task|
  task.libs << 'test'
  task.pattern = 'test/**/*_test.rb'
  task.warning = true
end

default = [:test]
begin
  require 'rubocop/rake_task'
  RuboCop::RakeTask.new
  default << :rubocop
rescue LoadError
  # RuboCop is in the lint group, which test-only installs leave out.
end

task default: default
