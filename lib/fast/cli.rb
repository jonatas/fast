# frozen_string_literal: true

require 'fast'
require 'fast/version'
require 'fast/sql'
require 'coderay'
require 'optparse'
require 'ostruct'

# Fast is a powerful tool to search through the command line for specific Ruby code.
# It defines #report and #highlight functions that can be used to pretty print
# code and results from the search.
module Fast
  module_function

  # Highligh some source code based on the node.
  # Useful for printing code with syntax highlight.
  # @param show_sexp [Boolean] prints node expression instead of code
  # @param colorize [Boolean] skips `CodeRay` processing when false.
  def highlight(node, show_sexp: false, colorize: true, sql: false)
    output =
      if node.respond_to?(:loc) && !show_sexp
        wrap_source_range(node).source
      else
        node
      end
    return output unless colorize

    CodeRay.scan(output, sql ? :sql : :ruby).term
  end

  # Fixes initial spaces to print the line since the beginning
  # and fixes end of the expression including heredoc strings.
  def wrap_source_range(node)
    expression = node.loc.expression
    Parser::Source::Range.new(
      expression.source_buffer,
      first_position_from_expression(node),
      last_position_from_expression(node) || expression.end_pos
    )
  end

  # If a method call contains a heredoc, it should print the STR around it too.
  def last_position_from_expression(node)
    internal_heredoc = node.each_descendant(:str).select { |n| n.loc.respond_to?(:heredoc_end) }
    internal_heredoc.map { |n| n.loc.heredoc_end.end_pos }.max if internal_heredoc.any?
  end

  # If a node is the first on it's line, print since the beginning of the line
  # to show the proper whitespaces for identing the next lines of the code.
  def first_position_from_expression(node)
    expression = node.loc.expression
    if node.respond_to?(:parent) && node.parent && node.parent.loc.expression.line != expression.line
      expression.begin_pos - expression.column
    else
      expression.begin_pos
    end
  end

  # Combines {.highlight} with files printing file name in the head with the
  # source line.
  # @param result [Parser::AST::Node]
  # @param show_sexp [Boolean] Show string expression instead of source
  # @param file [String] Show the file name and result line before content
  # @param headless [Boolean] Skip printing the file name and line before content
  # @example
  #   Fast.report(result, file: 'file.rb')
  def report(result, show_link: false, show_permalink: false, show_sexp: false, file: nil, headless: false, bodyless: false, colorize: true) # rubocop:disable Metrics/ParameterLists
    if file
      line = result.loc.expression.line if result.is_a?(Parser::AST::Node)
      if show_link
        puts(result.link)
      elsif show_permalink
        puts(result.permalink)
      elsif !headless
        puts(highlight("# #{file}:#{line}", colorize: colorize))
      end
    end
    puts(highlight(result, show_sexp: show_sexp, colorize: colorize)) unless bodyless
  end

  # Command Line Interface for Fast
  class Cli # rubocop:disable Metrics/ClassLength
    attr_reader :pattern, :show_sexp, :pry, :from_code, :similar, :help
    def initialize(args)
      args = args.dup
      args = replace_args_with_shortcut(args) if shortcut_name_from(args)
      @colorize = STDOUT.isatty
      option_parser.parse! args
      @pattern, @files = extract_pattern_and_files(args)

      @sql ||= @files.any? && @files.all? { |file| file.end_with?('.sql') }
      require 'fast/sql' if @sql
    end

    def option_parser # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
      @option_parser ||= OptionParser.new do |opts| # rubocop:disable Metrics/BlockLength
        opts.banner = 'Usage: fast expression <files> [options]'
        opts.on('-d', '--debug', 'Debug fast engine') do
          @debug = true
        end

        opts.on('--ast', 'Print AST instead of code') do
          @show_sexp = true
        end

        opts.on('--link', 'Print link to repository URL') do
          require 'fast/git'
          @show_link = true
        end

        opts.on('--permalink', 'Print permalink to repository URL') do
          require 'fast/git'
          @show_permalink = true
        end

        opts.on('-p', '--parallel', 'Paralelize search') do
          @parallel = true
        end

        opts.on("--sql", "Use SQL instead of Ruby") do
          @sql = true
        end

        opts.on('--captures', 'Print only captures of the patterns and skip node results') do
          @captures = true
        end

        opts.on('--headless', 'Print results without the file name in the header') do
          @headless = true
        end

        opts.on('--bodyless', 'Print results without the code details') do
          @bodyless = true
        end

        opts.on('--pry', 'Jump into a pry session with results') do
          @pry = true
          require 'pry'
        end

        opts.on('-s', '--similar', 'Search for similar code.') do
          @similar = true
        end

        opts.on('--no-color', 'Disable color output') do
          @colorize = false
        end

        opts.on('--from-code', 'From code') do
          @from_code = true
        end

        opts.on_tail('--version', 'Show version') do
          puts Fast::VERSION
          exit
        end

        opts.on_tail('-h', '--help', 'Show help. More at https://jonatas.github.io/fast') do
          @help = true
        end
      end
    end

    def replace_args_with_shortcut(args)
      shortcut_name = shortcut_name_from(args)
      shortcut = find_shortcut(shortcut_name)

      if shortcut.single_run_with_block?
        shortcut.run
        exit
      else
        shortcut.args
      end
    end

    # Run a new command line interface digesting the arguments
    def self.run!(argv)
      argv = argv.dup
      new(argv).run!
    end

    # Show help or search for node patterns
    def run!
      raise 'pry and parallel options are incompatible :(' if @parallel && @pry

      if @help || @files.empty? && @pattern.nil?
        puts option_parser.help
        return
      end

      if @similar
        ast = Fast.public_send( @sql ? :parse_sql : :ast, @pattern)
        @pattern = Fast.expression_from(ast)
        debug "Search similar to #{@pattern}"
      elsif @from_code
        ast = Fast.public_send( @sql ? :parse_sql : :ast, @pattern)
        @pattern = ast.to_sexp
        if @sql
          @pattern.gsub!(/\b-\b/,'_')
        end
        debug "Search from code to #{@pattern}"
      end

      if @files.empty?
        ast ||= Fast.public_send( @sql ? :parse_sql : :ast, @pattern)
        puts Fast.highlight(ast, show_sexp: @show_sexp, colorize: @colorize, sql: @sql)
      else
        search
      end
    end

    # Create fast expression from node pattern using the command line
    # @return [Array<Fast::Find>] with the expression from string.
    def expression
      Fast.expression(@pattern)
    end

    # Search for each file independent.
    # If -d (debug option) is enabled, it will output details of each search.
    # If capture option is enabled it will only print the captures, otherwise it
    # prints all the results.
    def search
      return Fast.debug(&method(:execute_search)) if debug_mode?

      execute_search do |file, results|
        results.each do |result|
          binding.pry if @pry # rubocop:disable Lint/Debugger
          report(file, result)
        end
      end
    end

    # Executes search for all files yielding the results
    # @yieldparam [String, Array] with file and respective search results
    def execute_search(&on_result)
      Fast.public_send(search_method_name,
                       @pattern,
                       @files,
                       parallel: parallel?,
                       on_result: on_result)
    end

    # @return [Symbol] with `:capture_all` or `:search_all` depending the command line options
    def search_method_name
      @captures ? :capture_all : :search_all
    end

    # @return [Boolean] true when "-d" or "--debug" option is passed
    def debug_mode?
      @debug == true
    end

    # Output information if #debug_mode? is true.
    def debug(*info)
      puts(info) if debug_mode?
    end

    def parallel?
      @parallel == true
    end

    # Report results using the actual options binded from command line.
    # @see Fast.report
    def report(file, result)
      Fast.report(result,
                  file: file,
                  show_link: @show_link,
                  show_permalink: @show_permalink,
                  show_sexp: @show_sexp,
                  headless: @headless,
                  bodyless: @bodyless,
                  colorize: @colorize)
    end

    def shortcut_name_from(args)
      command = args.find { |arg| !arg.start_with?('-') }
      return unless command&.start_with?('.')

      command[1..]
    end

    def extract_pattern_and_files(args)
      return [nil, []] if args.empty?

      files_start = args.index { |arg| File.exist?(arg) || File.directory?(arg) }
      if files_start
        [args[0...files_start].join(' '), args[files_start..]]
      else
        [args.join(' '), []]
      end
    end

    # Find shortcut by name. Preloads all `Fastfiles` before start.
    # @param name [String]
    def find_shortcut(name)
      unless defined? Fast::Shortcut
        require 'fast/shortcut'
        Fast.load_fast_files!
      end

      shortcut = Fast.shortcuts[name.to_sym]
      exit_shortcut_not_found(name) unless shortcut
      shortcut
    end

    # Exit process with warning message bolding the shortcut that was not found.
    # Prints available shortcuts as extra help and exit with code 1.
    def exit_shortcut_not_found(name)
      puts "Shortcut \033[1m#{name}\033[0m not found :("
      if Fast.shortcuts.any?
        puts "Available shortcuts are: #{Fast.shortcuts.keys.join(', ')}."
        Fast.load_fast_files!
      end
      exit 1
    end
  end
end
