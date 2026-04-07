# frozen_string_literal: true

require 'spec_helper'
require 'fast/gains'
require 'fileutils'
require 'json'

RSpec.describe Fast::Gains do
  let(:temp_dir) { File.join(Dir.pwd, 'tmp_gains') }
  let(:temp_file) { File.join(temp_dir, 'gains.json') }

  before do
    stub_const('Fast::Gains::STORAGE_DIR', temp_dir)
    stub_const('Fast::Gains::STORAGE_FILE', temp_file)
    FileUtils.mkdir_p(temp_dir)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe '#record_search' do
    it 'increments files_count and total_bytes_searched' do
      file = File.join(temp_dir, 'test.rb')
      File.write(file, 'puts "hello"')
      
      subject.record_search(file)
      
      expect(subject.files_count).to eq(1)
      expect(subject.total_bytes_searched).to eq(File.size(file))
    end
  end

  describe '#record_report' do
    it 'increments total_bytes_reported' do
      subject.record_report('test content')
      expect(subject.total_bytes_reported).to eq('test content'.bytesize)
    end
  end

  describe '#record_match' do
    it 'increments matched_files_count for unique files' do
      subject.record_match('file1.rb')
      subject.record_match('file1.rb')
      subject.record_match('file2.rb')
      
      expect(subject.matched_files_count).to eq(2)
    end
  end

  describe '#save!' do
    it 'saves data to the JSON file if there are reports' do
      file = File.join(temp_dir, 'test.rb')
      File.write(file, 'test content')
      
      subject.record_search(file)
      subject.record_report('match')
      subject.save!
      
      expect(File.exist?(temp_file)).to be true
      data = JSON.parse(File.read(temp_file))
      expect(data.last['bytes_searched']).to eq(File.size(file))
      expect(data.last['bytes_reported']).to eq('match'.bytesize)
    end

    it 'does NOT save data if there are no reports (honest gain)' do
      file = File.join(temp_dir, 'test.rb')
      File.write(file, 'test content')
      
      subject.record_search(file)
      subject.save!
      
      expect(File.exist?(temp_file)).to be false
    end
  end

  describe '.report' do
    it 'prints a message if no history exists' do
      expect { described_class.report }.to output(/No gains recorded yet/).to_stdout
    end

    context 'with history' do
      let(:now) { Time.now.iso8601 }
      let(:data) do
        [
          { timestamp: now, command: 'fast test', files_count: 10, bytes_searched: 1000, bytes_reported: 100, savings_percent: 90.0 },
          { timestamp: now, command: 'mcp:search', files_count: 5, bytes_searched: 500, bytes_reported: 50, savings_percent: 90.0 }
        ]
      end

      before do
        File.write(temp_file, JSON.generate(data))
      end

      it 'prints a breakdown if both CLI and MCP exist' do
        expect { described_class.report }.to output(/Fast Gains Report \(CLI\)/).to_stdout
        expect { described_class.report }.to output(/Fast Gains Report \(MCP\)/).to_stdout
        expect { described_class.report }.to output(/Fast Gains Report \(Total\)/).to_stdout
      end

      it 'prints only CLI report when filtered' do
        expect { described_class.report('cli') }.to output(/Fast Gains Report \(CLI\)/).to_stdout
        expect { described_class.report('cli') }.not_to output(/Fast Gains Report \(MCP\)/).to_stdout
      end

      it 'prints only MCP report when filtered' do
        expect { described_class.report('mcp') }.to output(/Fast Gains Report \(MCP\)/).to_stdout
        expect { described_class.report('mcp') }.not_to output(/Fast Gains Report \(CLI\)/).to_stdout
      end
    end
  end
end
