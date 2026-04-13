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
    Fast.enable_gain_track!
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
    it 'saves data to a unique JSON file if there are reports' do
      file = File.join(temp_dir, 'test.rb')
      File.write(file, 'test content')
      
      subject.record_search(file)
      subject.record_report('match')
      subject.save!
      
      temp_files = Dir.glob(File.join(temp_dir, 'gains-*.json'))
      expect(temp_files).not_to be_empty
      
      described_class.consolidate!
      
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
      
      temp_files = Dir.glob(File.join(temp_dir, 'gains-*.json'))
      expect(temp_files).to be_empty
    end

    it 'saves multiple runs to different files and consolidates them' do
      # Run 1
      g1 = Fast::Gains.new('run 1')
      File.write(File.join(temp_dir, 'f1.rb'), 'hello')
      g1.record_search(File.join(temp_dir, 'f1.rb'))
      g1.record_report('match 1')
      g1.save!

      # Run 2
      g2 = Fast::Gains.new('run 2')
      File.write(File.join(temp_dir, 'f2.rb'), 'world')
      g2.record_search(File.join(temp_dir, 'f2.rb'))
      g2.record_report('match 2')
      g2.save!

      # Verify two temp files exist
      temp_files = Dir.glob(File.join(temp_dir, 'gains-*.json'))
      expect(temp_files.size).to eq(2)
      expect(File.exist?(temp_file)).to be false

      # Consolidate
      data = Fast::Gains.consolidate!

      # Verify temp files are gone and gains.json exists
      expect(Dir.glob(File.join(temp_dir, 'gains-*.json'))).to be_empty
      expect(File.exist?(temp_file)).to be true
      
      expect(data.size).to eq(2)
      expect(data.map { |h| h[:command] }).to contain_exactly('run 1', 'run 2')
      expect(data.last[:reports]).to contain_exactly('match 2')
    end

    it 'keeps reports only for the latest runs' do
      6.times do |i|
        g = Fast::Gains.new("run #{i}")
        File.write(File.join(temp_dir, "f#{i}.rb"), "content #{i}")
        g.record_search(File.join(temp_dir, "f#{i}.rb"))
        g.record_report("patch #{i}")
        g.save!
      end

      Fast::Gains.consolidate!

      data = JSON.parse(File.read(temp_file), symbolize_names: true)
      expect(data.size).to eq(6)
      
      # Run 0 should not have reports
      expect(data[0][:reports]).to be_nil
      # Run 5 should have reports
      expect(data[5][:reports]).to contain_exactly('patch 5')
      # Run 1 should have reports (since it's index 1 in 6 entries, it's one of the last 5)
      expect(data[1][:reports]).to contain_exactly('patch 1')
    end

    it 'does NOT record or save anything if disabled' do
      Fast.disable_gain_track!
      file = File.join(temp_dir, 'test.rb')
      File.write(file, 'test content')
      
      subject.record_search(file)
      subject.record_match(file)
      subject.record_report('match')
      subject.save!
      
      expect(subject.files_count).to eq(0)
      expect(subject.matched_files_count).to eq(0)
      expect(subject.total_bytes_reported).to eq(0)
      
      temp_files = Dir.glob(File.join(temp_dir, 'gains-*.json'))
      expect(temp_files).to be_empty
    end

    it 'does NOT record or save anything if FAST_GAINS=0' do
      stub_const('ENV', ENV.to_h.merge('FAST_GAINS' => '0'))
      file = File.join(temp_dir, 'test.rb')
      File.write(file, 'test content')
      
      subject.record_search(file)
      subject.record_match(file)
      subject.record_report('match')
      subject.save!
      
      expect(subject.files_count).to eq(0)
      
      temp_files = Dir.glob(File.join(temp_dir, 'gains-*.json'))
      expect(temp_files).to be_empty
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
