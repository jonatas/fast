# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'time'

module Fast
  # Gains tracks the efficiency of the searches and code explorations.
  # It measures bytes searched vs. bytes reported to quantify savings.
  class Gains
    STORAGE_DIR = File.expand_path('~/.fast')
    STORAGE_FILE = File.join(STORAGE_DIR, 'gains.json')

    def self.storage_dir
      Fast.gains_dir || STORAGE_DIR
    end

    def self.storage_file
      File.join(storage_dir, 'gains.json')
    end

    attr_reader :command, :start_time, :total_bytes_searched, :total_bytes_reported, :files_count, :matched_files_count

    def initialize(command = nil)
      @command = command
      @start_time = Time.now
      @total_bytes_searched = 0
      @total_bytes_reported = 0
      @files_count = 0
      @matched_files_count = 0
      @files_with_matches = []
    end

    def record_search(file)
      return unless Fast.gain_tracking_enabled?
      @files_count += 1
      size = File.size(file) rescue 0
      @total_bytes_searched += size
    end

    def record_match(file)
      return unless Fast.gain_tracking_enabled?
      unless @files_with_matches.include?(file)
        @files_with_matches << file
        @matched_files_count += 1
      end
    end

    def record_report(content)
      return unless Fast.gain_tracking_enabled?
      @total_bytes_reported += content.to_s.bytesize
    end

    def save!
      return unless Fast.gain_tracking_enabled?
      return if @total_bytes_searched.zero?
      return if @total_bytes_reported.zero?

      data = {
        timestamp: @start_time.iso8601,
        command: @command,
        files_count: @files_count,
        matched_files_count: @matched_files_count,
        bytes_searched: @total_bytes_searched,
        bytes_reported: @total_bytes_reported
      }

      FileUtils.mkdir_p(self.class.storage_dir) rescue nil
      temp_filename = File.join(self.class.storage_dir, "gains-#{Time.now.to_f}-#{Process.pid}.json")
      File.write(temp_filename, JSON.generate(data)) rescue nil
      
      self.class.consolidate!
    end

    def self.consolidate!
      return unless File.writable?(storage_dir) || File.writable?(File.dirname(storage_dir))
      FileUtils.mkdir_p(storage_dir) rescue nil
      
      File.open(storage_file, File::RDWR|File::CREAT, 0644) do |f|
        f.flock(File::LOCK_EX)
        
        content = f.read
        all_data = JSON.parse(content, symbolize_names: true) rescue [] unless content.empty?
        all_data ||= []
        
        temp_files = Dir.glob(File.join(storage_dir, 'gains-*.json'))
        temp_files.each do |file|
          begin
            all_data << JSON.parse(File.read(file), symbolize_names: true)
            File.delete(file)
          rescue
            # Skip corrupted files
          end
        end

        # Keep only the last 1000 runs to avoid file growing too much
        all_data = all_data.last(1000)

        f.rewind
        f.truncate(0)
        f.write(JSON.pretty_generate(all_data))
        all_data
      end
    rescue
      # Fail silently if not possible to write
      []
    end

    def self.summarize(data)
      return [] if data.nil? || data.empty?
      data.group_by do |h|
        timestamp = h[:timestamp] || Time.now.iso8601
        hour = Time.parse(timestamp).strftime('%Y-%m-%d %H:00')
        category = h[:command]&.start_with?('mcp:') ? 'mcp' : 'cli'
        [hour, category]
      end.map do |(hour, category), runs|
        {
          hour: hour,
          category: category,
          files_count: runs.sum { |r| r[:files_count] || 0 },
          matched_files_count: runs.sum { |r| r[:matched_files_count] || 0 },
          bytes_searched: runs.sum { |r| r[:bytes_searched] || 0 },
          bytes_reported: runs.sum { |r| r[:bytes_reported] || 0 },
          runs_count: runs.size
        }
      end.sort_by { |h| h[:hour] }
    end

    def self.report(filter = nil)
      all_raw_history = consolidate!
      return puts "No gains recorded yet. Start searching with `fast`!" if all_raw_history.empty?

      all_history = summarize(all_raw_history)

      title = filter ? "Fast Gains Report (#{filter.upcase})" : "Fast Gains Report"
      history = filter ? all_history.select { |h| h[:category] == filter } : all_history
      
      render_report(title, history)
    end

    def self.render_report(title, history)
      return puts "No gains recorded for this category." if history.empty?

      total_searched = history.sum { |h| h[:bytes_searched] || 0 }
      total_reported = history.sum { |h| h[:bytes_reported] || 0 }
      total_files = history.sum { |h| h[:files_count] || 0 }
      total_matched_files = history.sum { |h| h[:matched_files_count] || 0 }
      total_savings = total_searched - total_reported
      avg_percent = total_searched.zero? ? 0 : 100.0 * (1.0 - (total_reported.to_f / total_searched))
      total_runs = history.sum { |h| h[:runs_count] || 1 }

      puts "\e[1m#{title}\e[0m"
      puts '-' * title.length
      puts "Total Bytes Searched: #{format_bytes(total_searched)} (#{total_files} files)"
      puts "Total Bytes Reported: #{format_bytes(total_reported)} (#{total_matched_files} files matched)"
      puts "Total Savings:       \e[32m#{format_bytes(total_savings)} (#{avg_percent.round(2)}%)\e[0m"
      puts "Commands executed:    #{total_runs}"

      categories = history.map { |h| h[:category] }.uniq
      if categories.size > 1
        print "Breakdown:           "
        parts = categories.map do |cat|
          cat_history = history.select { |h| h[:category] == cat }
          cat_runs = cat_history.sum { |h| h[:runs_count] || 1 }
          "#{cat.upcase}: #{cat_runs}"
        end
        puts parts.join(", ")
      end

      puts ''
      render_hourly_summary(history)
    end

    def self.render_hourly_summary(history)
      puts "Savings by Hour (last 12 hours):"
      
      hourly_data = history.group_by { |h| h[:hour] }.sort.last(12)
      max_savings = hourly_data.map { |_, entries| entries.sum { |h| h[:bytes_searched] - h[:bytes_reported] } }.max
      max_savings = 1 if max_savings.to_i.zero?

      hourly_data.each do |hour, entries|
        searched = entries.sum { |h| h[:bytes_searched] || 0 }
        reported = entries.sum { |h| h[:bytes_reported] || 0 }
        savings = searched - reported
        percent = searched.zero? ? 0 : 100.0 * (1.0 - (reported.to_f / searched))
        
        bar_length = (20.0 * [savings, 0].max / max_savings).to_i
        bar = "█" * bar_length
        
        printf "%s | %-20s | %6.2f%% efficiency\n", 
               hour[5..15], bar, percent
      end
    end

    def self.format_bytes(bytes)
      if bytes < 1024
        "#{bytes} B"
      elsif bytes < 1024**2
        "#{(bytes / 1024.0).round(2)} KB"
      elsif bytes < 1024**3
        "#{(bytes / 1024.0**2).round(2)} MB"
      else
        "#{(bytes / 1024.0**3).round(2)} GB"
      end
    end
  end
end
