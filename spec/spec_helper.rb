# frozen_string_literal: true

require 'bundler/setup'
require 'simplecov'

SimpleCov.start

require 'fast'
require 'rspec/its'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.around(:example, only: :local) do |example|
    if ENV['TRAVIS']
      example.skip
    else
      example.run
    end
  end
end
