# frozen_string_literal: true

require 'fast'
require 'open3'
require 'ostruct'
require 'fileutils'

# Usage instructions:
# 1. Add the following to your project's Gemfile: gem 'ffast' (yes, two "f"s)
# 2. Copy this file to your Rails project root directory
# 3. Run: bundle exec ruby build_stubbed_and_let_it_be_experiment.rb

# List of spec files you want to experiment with. One per line.
FILE_NAMES = %w[
  # spec/model/foo_spec.rb
  # spec/model/bar_spec.rb
]

def execute_rspec(file_name)
  rspec_command = "bin/spring rspec --fail-fast --format progress #{file_name}"
  stdout_str, stderr_str, status = Open3.capture3(rspec_command)
  execution_time = /Finished in (.*?) seconds/.match(stdout_str)[1]
  print stderr_str.gsub(/Running via Spring preloader.*?$/, '').chomp unless status.success?
  OpenStruct.new(success: status.success?, execution_time: execution_time)
end

def delete_temp_files(original_file_name)
  file_path = File.dirname(original_file_name)
  file_name = File.basename(original_file_name)
  Dir.glob("#{file_path}/experiment*#{file_name}").each { |file| File.delete(file)}
end

FILE_NAMES.each do |original_file_name|
  Fast.experiment('RSpec/ReplaceCreateWithBuildStubbed') do
    lookup original_file_name
    search '(block (send nil let (sym _)) (args) $(send nil create))'
    edit { |_, (create)| replace(create.loc.selector, 'build_stubbed') }
    policy { |experiment_file_name| execute_rspec(experiment_file_name) }
  end.run

  Fast.experiment('RSpec/LetItBe') do
    lookup original_file_name
    search '(block $(send nil let! (sym _)) (args) (send nil create))'
    edit { |_, (let)| replace(let.loc.selector, 'let_it_be') }
    policy { |experiment_file_name| execute_rspec(experiment_file_name) }
  end.run

  delete_temp_files(original_file_name)
end


