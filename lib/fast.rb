require 'bundler/setup'
require 'parser'
require 'parser/current'

module Fast
  VERSION = "0.1.0"
  LITERAL = {
    '...' => -> (node) { node && node.children.any? },
    '_'   => -> (node) { !node.nil? },
    'nil' => nil
  }

  TOKENIZER = %r/
    [\+\-\/\*\\!]         # operators or negation
    |
    \d+\.\d*              # decimals and floats
    |
    _                     # something not nil: match
    |
    \.{3}                 # a node with children: ...
    |
    \[|\]                 # square brackets `[` and `]` for all
    |
    \^                    # node has children with
    |
    \?                    # maybe expression
    |
    [\d\w_]+[\\!\?]?      # method names or numbers
    |
    \(|\)                 # parens `(` and `)` for tuples
    |
    \{|\}                 # curly brackets `{` and `}` for any
    |
    \$                    # capture
    |
    \\\d                  # find using captured expression
  /x

  def self.match?(ast, search)
    Matcher.new(ast, search).match?
  end

  def self.replace(ast, search, replacement)
    buffer = Parser::Source::Buffer.new('replacement')
    buffer.source = ast.loc.expression.source
    to_replace = search(ast, search)
    types = to_replace.grep(Parser::AST::Node).map(&:type).uniq
    rewriter = Rewriter.new
    rewriter.buffer = buffer
    rewriter.search = search
    rewriter.replacement = replacement
    rewriter.affect_types(*types)
    rewriter.rewrite(buffer, ast)
  end

  def self.replace_file(file, search, replacement)
    ast = ast_from_file(file)
    replace(ast, search, replacement)
  end

  def self.search_file pattern, file
    node = ast_from_file(file)
    search node, pattern
  end

  def self.search node, pattern
    if (match = Fast.match?(node, pattern))
      yield node, match if block_given?
      match != true ? [node, match] : [node]
    else
      if node && node.children.any?
        node.children
          .grep(Parser::AST::Node)
          .flat_map{|e| search(e, pattern) }.compact.uniq.flatten
      end
    end
  end

  def self.capture node, pattern
    res =
      if (match = Fast.match?(node, pattern))
        match == true ? node : match
      else
        if node && node.children.any?
          node.children
            .grep(Parser::AST::Node)
            .flat_map{|child| capture(child, pattern) }.compact.flatten
        end
      end
    res&.size == 1 ? res[0] : res
  end

  def self.ast_from_file(file)
    Parser::CurrentRuby.parse(IO.read(file))
  end

  def self.buffer_for(file)
    buffer = Parser::Source::Buffer.new(file.to_s)
    buffer.source = IO.read(file)
    buffer
  end

  def self.expression(string)
    ExpressionParser.new(string).parse
  end

  def self.debug
    return yield if Find.instance_methods.include?(:debug)
    Find.class_eval do
      alias original_match_recursive match_recursive
      def match_recursive a, b
        match = original_match_recursive(a, b)
        debug(a, b, match)
        match

      end
      def debug a, b, match
        puts "#{b} == #{a} # => #{match}"
      end
    end

    result = yield

    Find.class_eval do
      alias match_recursive original_match_recursive
      remove_method :debug
    end
    result
  end

  def self.ruby_files_from(*files)
    directories = files.select(&File.method(:directory?))

    if directories.any?
      files -= directories
      files |= directories.flat_map{|dir|Dir["#{dir}/**/*.rb"]}
      files.uniq!
    end
    files
  end

  class Rewriter < Parser::Rewriter
    attr_reader :match_index
    attr_accessor :buffer, :search, :replacement
    def initialize *args
      super
      @match_index = 0
    end
    def match? node
      Fast.match?(node, search)
    end
    def affect_types(*types)
      types.map do |type|
        self.class.send :define_method, "on_#{type}" do |node|
          if captures = match?(node)
            @match_index += 1
            if replacement.parameters.length == 1
              instance_exec node, &replacement
            else
              instance_exec node, captures, &replacement
            end
          end
          super(node)
        end
      end
    end
  end

  class ExpressionParser
    def initialize(expression)
      @tokens = expression.scan TOKENIZER
    end

    def next_token
      @tokens.shift
    end

    def parse
      case (token = next_token)
      when '(' then parse_until_peek(')')
      when '{' then Any.new(parse_until_peek('}'))
      when '[' then All.new(parse_until_peek(']'))
      when '$' then Capture.new(parse)
      when '!' then (@tokens.any? ? Not.new(parse) : Find.new(token))
      when '?' then Maybe.new(parse)
      when '^' then Parent.new(parse)
      when '\\' then FindWithCapture.new(parse)
      else Find.new(token)
      end
    end

    def parse_until_peek(token)
      list = []
      list << parse until @tokens.empty? || @tokens.first == token
      next_token
      list
    end
  end

  class Find < Struct.new(:token)
    def initialize(token)
      self.token = token
    end

    def match?(node)
      match_recursive(node, valuate(token))
    end

    def match_recursive(node, expression)
      if expression.respond_to?(:call)
        expression.call(node)
      elsif expression.is_a?(Find)
        expression.match?(node)
      elsif expression.is_a?(Symbol)
        type = node.respond_to?(:type) ? node.type : node
        type == expression
      elsif expression.respond_to?(:shift)
        expression.each_with_index.all? do |exp, i|
          match_recursive(i == 0 ? node : node.children[i-1], exp)
        end
      else
        node == expression
      end
    end

    def to_s
      "f[#{[*token].join(', ')}]"
    end

    private

    def valuate(token)
      if token.is_a?(String)
        if LITERAL.has_key?(token)
          valuate(LITERAL[token])
        elsif token =~ /\d+\.\d*/
          token.to_f
        elsif token =~ /\d+/
          token.to_i
        else
          token.to_sym
        end
      else
        token
      end
    end
  end

  class FindWithCapture <  Find
    attr_writer :previous_captures

    def initialize(token)
      token = token.token if token.respond_to?(:token)
      raise 'You must use captures!' unless token
      @capture_index = token.to_i
    end

    def match?(node)
      node == @previous_captures[@capture_index-1]
    end

    def to_s
      "fc[\\#{@capture_index}]"
    end
  end

  class Capture <  Find
    attr_reader :captures
    def initialize(token)
      super
      @captures = []
    end

    def match? node
      if super
        @captures << node
      end
    end

    def to_s
      "c[#{token} $: #{@captures}]"
    end
  end

  class Parent <  Find
    alias match_node match?
    def match? node
      node.children.grep(Parser::AST::Node).any?(&method(:match_node))
    end

    def to_s
      "^#{token}"
    end
  end

  class Any < Find
    def match?(node)
      token.any?{|expression| Fast.match?(node, expression) }
    end

    def to_s
      "any[#{token}]"
    end
  end

  class All < Find
    def match?(node)
      token.all?{|expression|expression.match?(node) }
    end

    def to_s
      "all[#{token}]"
    end
  end

  class Not < Find
    def match?(node)
      !super
    end
  end

  class Maybe < Find
    def match?(node)
      node.nil? || super
    end
  end

  class Matcher
    def initialize(ast, fast)
      @ast = ast
      if fast.is_a?(String)
        @fast = Fast.expression(fast)
      else
        @fast = fast.map(&Find.method(:new))
      end
      @captures = []
    end

    def match?(ast=@ast, fast=@fast)
      head,*tail = fast
      return false unless head.match?(ast)
      if tail.empty?
        return ast == @ast ? find_captures : true # root node
      end
      child = ast.children
      tail.each_with_index.each do |token, i|
        matched =
          if token.is_a?(Array)
            match?(child[i], token)
          elsif token.is_a?(Fast::FindWithCapture)
            token.previous_captures = find_captures
            token.match?(child[i])
          else
            token.match?(child[i])
          end
        return false unless matched
      end

      find_captures
    end

    def has_captures?(fast=@fast)
      case fast
      when Capture
        true
      when Array
        fast.any?(&method(:has_captures?))
      when Find
        has_captures?(fast.token)
      end
    end

    def find_captures(fast=@fast)
      return true if fast == @fast && !has_captures?(fast)
      case fast
      when Capture
        fast.captures
      when Array
        fast.flat_map(&method(:find_captures)).compact
      when Find
        find_captures(fast.token)
      end
    end
  end
  
  class Experiment
    attr_reader :ok_experiments, :fail_experiments
    def initialize(file, search)
      @file = file
      @ast = Fast.ast_from_file(file)
      @search = search
      @ok_experiments = []
      @fail_experiments = []
    end
    def experimental_filename(combination)
      parts = @file.split('/')
      dir = parts[0..-2]
      filename = "experiment_#{[*combination].join('_')}_#{parts[-1]}"
      File.join(*dir, filename)
    end

    def ok(occurrence)
      @ok_experiments << occurrence
      if occurrence.is_a?(Array)
        occurrence.each do |element|
          @ok_experiments.delete(element)
        end
      end
    end

    def fail(occurrence)
      @fail_experiments << occurrence
    end

    def search_cases
      Fast.search(@ast, @search) || []
    end

    def partial_replace(replacement, *indices)
      new_content = Fast.replace_file @file, @search, -> (node,*captures) do
        if indices.nil? || indices.empty? || indices.include?(match_index)
          instance_exec(node, *captures, &replacement)
        end
      end
      if new_content
        write_experiment_file(indices, new_content)
        new_content
      end
    end

    def write_experiment_file(index, new_content)
      filename = experimental_filename(index)
      File.open(filename, 'w+') {|f|f.puts new_content}
      filename
    end

    def suggest_combinations
      if @ok_experiments.empty? && @fail_experiments.empty?
        search_cases.size.times.map(&:next)
      else
        @ok_experiments
          .combination(2)
          .map{|e|e.flatten.uniq.sort}
          .uniq - @fail_experiments - @ok_experiments
      end
    end

    def done!
      count_executed_combinations = @fail_experiments.size + @ok_experiments.size
      puts "Done with #{@file} after #{count_executed_combinations}"
      if perfect_combination = @ok_experiments.last
        puts "mv #{experimental_filename(perfect_combination)} #{@file}"
        `mv #{experimental_filename(perfect_combination)} #{@file}`
      end

    end

    def run(expression, replacement)
      partial_replace(expression, replacement) do |experiment_file|
        # run spec
        # report ok or fail
      end
    end
  end
end
