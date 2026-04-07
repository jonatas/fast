# frozen_string_literal: true

require 'spec_helper'
require 'fast/cli'
require 'fileutils'

RSpec.describe Fast::Cli do
  let(:temp_dir) { File.join(Dir.pwd, 'tmp_cli_gains') }
  let(:temp_file) { File.join(temp_dir, 'gains.json') }

  before do
    stub_const('Fast::Gains::STORAGE_DIR', temp_dir)
    stub_const('Fast::Gains::STORAGE_FILE', temp_file)
    FileUtils.mkdir_p(temp_dir)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe 'gains integration' do
    it 'records bytes searched and reported during a search' do
      test_file = File.join(temp_dir, 'sample.rb')
      File.write(test_file, 'def hello; end')

      cli = Fast::Cli.new(['(def hello)', test_file, '--no-color'])
      expect { cli.run! }.to output(/def hello/).to_stdout

      expect(File.exist?(temp_file)).to be true
      data = JSON.parse(File.read(temp_file)).last
      expect(data['bytes_searched']).to eq(File.size(test_file))
      expect(data['bytes_reported']).to be > 0
    end

    it 'calls Gains.report when .gains is the pattern' do
      expect(Fast::Gains).to receive(:report).with(nil)
      Fast::Cli.new(['.gains']).run!
    end

    it 'calls Gains.report with "mcp" filter when .gains mcp is the pattern' do
      expect(Fast::Gains).to receive(:report).with('mcp')
      Fast::Cli.new(['.gains', 'mcp']).run!
    end

    it 'calls Gains.report with "cli" filter when .gains cli is the pattern' do
      expect(Fast::Gains).to receive(:report).with('cli')
      Fast::Cli.new(['.gains', 'cli']).run!
    end

    it 'does not save gains if no results are found' do
      test_file = File.join(temp_dir, 'sample.rb')
      File.write(test_file, 'def hello; end')

      cli = Fast::Cli.new(['(def non_existent)', test_file])
      cli.run!

      expect(File.exist?(temp_file)).to be false
    end
  end
end
