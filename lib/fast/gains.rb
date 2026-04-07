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
      @files_count += 1
      size = File.size(file) rescue 0
      @total_bytes_searched += size
    end

    def record_match(file)
      unless @files_with_matches.include?(file)
        @files_with_matches << file
        @matched_files_count += 1
      end
    end

    def record_report(content)
      @total_bytes_reported += content.to_s.bytesize
    end

    def save!
      return if @total_bytes_searched.zero?
      return if @total_bytes_reported.zero? # Honest gain: skip if nothing was found

      data = history
      data << {
        timestamp: @start_time.iso8601,
        command: @command,
        files_count: @files_count,
        matched_files_count: @matched_files_count,
        bytes_searched: @total_bytes_searched,
        bytes_reported: @total_bytes_reported,
        savings_percent: savings_percent.round(2)
      }

      FileUtils.mkdir_p(STORAGE_DIR)
      File.write(STORAGE_FILE, JSON.pretty_generate(data))
    end

    def savings_percent
      return 0.0 if @total_bytes_searched.zero?
      
      100.0 * (1.0 - (@total_bytes_reported.to_f / @total_bytes_searched))
    end

    def history
      return [] unless File.exist?(STORAGE_FILE)

      JSON.parse(File.read(STORAGE_FILE), symbolize_names: true)
    rescue StandardError
      []
    end

    def self.report(filter = nil)
      all_history = new.history
      return puts "No gains recorded yet. Start searching with `fast`!" if all_history.empty?

      if filter == 'mcp'
        render_report('Fast Gains Report (MCP)', all_history.select { |h| h[:command]&.start_with?('mcp:') })
      elsif filter == 'cli'
        render_report('Fast Gains Report (CLI)', all_history.reject { |h| h[:command]&.start_with?('mcp:') })
      else
        mcp_history = all_history.select { |h| h[:command]&.start_with?('mcp:') }
        cli_history = all_history.reject { |h| h[:command]&.start_with?('mcp:') }

        if mcp_history.any? && cli_history.any?
          render_report('Fast Gains Report (CLI)', cli_history)
          puts "\n"
          render_report('Fast Gains Report (MCP)', mcp_history)
          puts "\n"
          render_report('Fast Gains Report (Total)', all_history)
        else
          render_report('Fast Gains Report', all_history)
        end
      end
    end

    def self.render_report(title, history)
      return puts "No gains recorded for this category." if history.empty?

      total_searched = history.sum { |h| h[:bytes_searched] || 0 }
      total_reported = history.sum { |h| h[:bytes_reported] || 0 }
      total_files = history.sum { |h| h[:files_count] || 0 }
      total_matched_files = history.sum { |h| h[:matched_files_count] || 0 }
      total_savings = total_searched - total_reported
      avg_percent = total_searched.zero? ? 0 : 100.0 * (1.0 - (total_reported.to_f / total_searched))

      puts "\e[1m#{title}\e[0m"
      puts '-' * title.length
      puts "Total Bytes Searched: #{format_bytes(total_searched)} (#{total_files} files)"
      puts "Total Bytes Reported: #{format_bytes(total_reported)} (#{total_matched_files} files matched)"
      puts "Total Savings:       \e[32m#{format_bytes(total_savings)} (#{avg_percent.round(2)}%)\e[0m"
      puts "Commands executed:    #{history.size}"
      puts ''

      show_graph(history.last(30))
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

    def self.show_graph(recent_history)
      puts "Recent Savings (last #{recent_history.size} runs):"
      max_savings = recent_history.map { |h| h[:bytes_searched] - h[:bytes_reported] }.max
      return if max_savings.to_i.zero?

      recent_history.each do |h|
        savings = h[:bytes_searched] - h[:bytes_reported]
        bar_length = (30.0 * savings / max_savings).to_i
        bar = "█" * bar_length
        printf "%10s | %-30s | %6.2f%%\n", h[:timestamp][5..15].tr('T', ' '), bar, h[:savings_percent]
      end
    end
  end
end
