# frozen_string_literal: true

require 'fast'
require 'fast/version'
require 'coderay'
require 'optparse'
require 'ostruct'

module Fast
  # Command Line Interface for Fast
  class Cli
    attr_reader :pattern, :show_sexp, :pry, :from_code, :similar, :help

    # rubocop:disable Metrics/MethodLength
    # rubocop:disable Metrics/AbcSize
    def initialize(args)
      @opt = OptionParser.new do |opts| # rubocop:disable Metrics/BlockLength
        opts.banner = 'Usage: fast expression <files> [options]'
        opts.on('-d', '--debug', 'Debug fast engine') do
          @debug = true
        end

        opts.on('--ast', 'Print AST instead of code') do
          @show_sexp = true
        end

        opts.on('--pry', 'Jump into a pry session with results') do
          @pry = true
        end

        opts.on('-c', '--code', 'Create a pattern from code example') do
          if @pattern
            @from_code = true
            @pattern = Fast.ast(@pattern).to_sexp
            debug 'Expression from AST:', @pattern
          end
        end

        opts.on('-s', '--similar', 'Search for similar code.') do
          @similar = true
          @pattern = Fast.expression_from(Fast.ast(@pattern))
          debug "Looking for code similar to #{@pattern}"
        end

        opts.on_tail('--version', 'Show version') do
          puts Fast::VERSION
          exit
        end

        opts.on_tail('-h', '--help', 'Show help. More at https://jonatas.github.io/fast') do
          @help = true
        end

        @pattern, @files = args.reject { |arg| arg.start_with? '-' }
      end
      @opt.parse! args

      @files = [*@files]
      @files.reject! { |arg| arg.start_with?('-') }
    end

    # rubocop:enable Metrics/MethodLength
    # rubocop:enable Metrics/AbcSize

    def self.run!(argv)
      argv = argv.dup
      new(argv).run!
    end

    def run!
      if @help || @files.empty? && @pattern.nil?
        puts @opt.help
      else
        search
      end
    end

    def expression
      Fast.expression(@pattern)
    end

    def search_file(file)
      if debug_mode?
        Fast.debug { Fast.search_file(expression, file) }
      else
        begin
          Fast.search_file(expression, file)
        rescue StandardError
          debug "Ops! An error occurred trying to search in #{expression.inspect} in #{file}", $ERROR_INFO, $ERROR_POSITION
          []
        end
      end
    end

    def search
      files.each do |file|
        results = search_file(file)
        next if results.nil? || results.empty?

        results.each do |result|
          if @pry
            require 'pry'
            binding.pry # rubocop:disable Lint/Debugger
          else
            report(result, file)
          end
        end
      end
    end

    def files
      Fast.ruby_files_from(*@files)
    end

    def debug_mode?
      @debug == true
    end

    def debug(*info)
      return unless @debug

      puts info
    end

    def report(result, file)
      Fast.report(result, file: file, show_sexp: @show_sexp)
    end
  end
end
