# frozen_string_literal: true

require 'bundler/setup'
require 'simplecov'

SimpleCov.start

require 'fast'
require 'fast/sql'
require 'rspec/its'

RSpec.shared_context :with_sql_file do
  let(:sql) { 'select * from my_table' }
  let(:file) { 'tmp.sql'}
  before :each do
    File.open(file, 'w') { |f| f.write(sql) }
  end
  after :each do
    File.delete(file) if File.exist?(file)
  end
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  helpers = Module.new do
    def s(type, *children)
      Fast::Node.new(type, children, buffer_name: respond_to?(:buffer_name) ? buffer_name : "sql")
    end
  end

  config.include(helpers)

  config.around(:example, only: :local) do |example|
    if ENV['TRAVIS']
      example.skip
    else
      example.run
    end
  end
end
