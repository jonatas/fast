# frozen_string_literal: true

require 'fast/prism_adapter'

module Fast
  class Summary
    VISIBILITIES = %i[public protected private].freeze

    def initialize(code_or_ast, file: nil, command_name: '.summary', level: nil)
      @file = file
      @command_name = command_name
      @level = normalize_level(level)
      @source =
        if code_or_ast.is_a?(String)
          code_or_ast
        elsif code_or_ast.respond_to?(:loc) && code_or_ast.loc.respond_to?(:expression)
          code_or_ast.loc.expression.source
        end

      @ast =
        if unsupported_template?
          nil
        elsif code_or_ast.is_a?(String)
          begin
            Fast.parse_ruby(code_or_ast, buffer_name: file || '(string)')
          rescue StandardError => e
            warn "Error parsing #{file || 'source'}: #{e.message}" if Fast.debugging
            nil
          end
        else
          code_or_ast
        end
    end

    def summarize
      if @ast
        print_node(@ast)
      elsif unsupported_template?
        puts "Unsupported template format for #{@command_name}: #{File.extname(@file)}"
      else
        puts "Unable to parse #{@file || 'source'} for #{@command_name}"
      end
    end

    def outline
      return [] unless @ast

      top_level_nodes(@ast).filter_map { |node| outline_for(node) }
    end

    private

    def unsupported_template?
      @file && !File.extname(@file).empty? && File.extname(@file) != '.rb'
    end

    def print_node(node, indent = '')
      return unless Fast.ast_node?(node)

      case node.type
      when :module
        puts "#{indent}module #{node_source(node.children[0])}"
        summarize_body(node.children[1], indent + '  ')
        puts "#{indent}end"
      when :class
        name = node_source(node.children[0])
        superclass = node.children[1] ? " < #{node_source(node.children[1])}" : ''
        puts "#{indent}class #{name}#{superclass}"
        summarize_body(node.children[2], indent + '  ')
        puts "#{indent}end"
      when :begin
        summarize_body(node, indent)
      else
        summarize_body(node, indent)
      end
    end

    def top_level_nodes(node)
      return [] unless Fast.ast_node?(node)

      case node.type
      when :begin
        node.children.select { |child| Fast.ast_node?(child) }
      else
        [node]
      end
    end

    def outline_for(node)
      return unless Fast.ast_node?(node)

      case node.type
      when :module
        summary = build_summary(node.children[1])
        build_outline_entry(node, summary, kind: :module, name: node_source(node.children[0]))
      when :class
        summary = build_summary(node.children[2])
        build_outline_entry(node, summary,
                            kind: :class,
                            name: node_source(node.children[0]),
                            superclass: node.children[1] && node_source(node.children[1]))
      else
        summary = build_summary(node)
        build_outline_entry(node, summary, kind: node.type, name: node.type.to_s)
      end
    end

    def build_outline_entry(node, summary, kind:, name:, superclass: nil)
      {
        file: @file,
        kind: kind,
        name: name,
        superclass: superclass,
        headline: outline_headline(kind, name, superclass),
        constants: summary[:constants],
        mixins: summary[:mixins],
        relationships: summary[:relationships],
        attributes: summary[:attributes],
        scopes: summary[:scopes],
        hooks: summary[:hooks],
        validations: summary[:validations],
        macros: summary[:macros],
        requires: summary[:requires],
        methods: summary[:methods],
        nested: summary[:nested].filter_map { |child| outline_for(child) },
        line: node.loc&.expression&.line
      }
    end

    def outline_headline(kind, name, superclass)
      case kind
      when :module
        "module #{name}"
      when :class
        superclass ? "class #{name} < #{superclass}" : "class #{name}"
      else
        name.to_s
      end
    end

    def summarize_body(body, indent)
      return unless Fast.ast_node?(body)

      summary = build_summary(body)

      if show_signals?
        print_requires(summary[:requires], indent)
        print_lines(summary[:constants], indent)
        print_lines(summary[:mixins], indent)
        print_lines(summary[:relationships], indent)
        print_lines(summary[:attributes], indent)
        print_section('Scopes', summary[:scopes], indent)
        print_section('Hooks', summary[:hooks], indent)
        print_section('Validations', summary[:validations], indent)
        print_section('Macros', summary[:macros], indent)
      end
      print_methods(summary[:methods], indent) if show_methods?
      summary[:nested].each { |child| print_node(child, indent) }
    end

    def build_summary(body)
      summary = {
        constants: [],
        mixins: [],
        relationships: [],
        attributes: [],
        scopes: [],
        hooks: [],
        validations: [],
        macros: [],
        requires: [],
        methods: VISIBILITIES.to_h { |visibility| [visibility, []] },
        nested: []
      }

      visibility = :public
      body_nodes(body).each do |node|
        next unless Fast.ast_node?(node)

        case node.type
        when :class, :module
          summary[:nested] << node
        when :casgn
          summary[:constants] << constant_line(node)
        when :def
          summary[:methods][visibility] << method_signature(node)
        when :defs
          summary[:methods][visibility] << singleton_method_signature(node)
        when :sclass
          summarize_singleton_class(node, summary, visibility)
        when :send
          visibility = visibility_change(node) || visibility
          categorize_send(node, summary)
        end
      end

      summary
    end

    def summarize_singleton_class(node, summary, default_visibility)
      visibility = default_visibility
      body_nodes(node.children[1]).each do |child|
        next unless Fast.ast_node?(child)

        case child.type
        when :def
          summary[:methods][visibility] << "def self.#{method_signature(child).delete_prefix('def ')}"
        when :send
          visibility = visibility_change(child) || visibility
          categorize_send(child, summary)
        when :class, :module
          summary[:nested] << child
        when :casgn
          summary[:constants] << constant_line(child)
        end
      end
    end

    def categorize_send(node, summary)
      return unless node.type == :send && node.children[0].nil?

      method_name = node.children[1]
      if Fast.match?('(send nil {has_many belongs_to has_one has_and_belongs_to_many} ...)', node)
        summary[:relationships] << compact_node_source(node)
      elsif Fast.match?('(send nil {attr_accessor attr_reader attr_writer} ...)', node)
        summary[:attributes] << attribute_line(node)
      elsif Fast.match?('(send nil {include extend prepend} ...)', node)
        summary[:mixins] << compact_node_source(node)
      elsif Fast.match?('(send nil scope ...)', node)
        summary[:scopes] << scope_line(node)
      elsif Fast.match?('(send nil validates ...)', node)
        summary[:validations] << node_source(node).delete_prefix('validates ')
      elsif Fast.match?('(send nil validate ...)', node)
        summary[:validations] << node_source(node).delete_prefix('validate ')
      elsif Fast.match?('(send nil {require require_relative} (str _))', node)
        summary[:requires] << required_path(node)
      elsif Fast.match?('(send nil {private protected public})', node)
        nil
      else
        summary[:hooks] << compact_node_source(node) if callback_macro?(method_name)
        summary[:macros] << compact_node_source(node) if macro_candidate?(node, summary)
      end
    end

    def macro_candidate?(node, summary)
      return false unless node.type == :send && node.children[0].nil?

      name = node.children[1]
      return false if callback_macro?(name)
      return false if Fast.match?('(send nil {has_many belongs_to has_one has_and_belongs_to_many} ...)', node)
      return false if Fast.match?('(send nil {attr_accessor attr_reader attr_writer} ...)', node)
      return false if Fast.match?('(send nil {include extend prepend} ...)', node)
      return false if Fast.match?('(send nil {require require_relative} (str _))', node)
      return false if Fast.match?('(send nil {scope validates validate private protected public} ...)', node)

      !summary[:macros].include?(compact_node_source(node))
    end

    def callback_macro?(method_name)
      method_name.to_s.start_with?('before_', 'after_', 'around_')
    end

    def visibility_change(node)
      return unless node.type == :send && node.children[0].nil?
      return unless VISIBILITIES.include?(node.children[1])
      return unless node.children.length == 2

      node.children[1]
    end

    def body_nodes(node)
      return [] unless node
      return node.children if node.type == :begin

      [node]
    end

    def normalize_level(level)
      return 3 if level.nil?

      [[level.to_i, 1].max, 3].min
    end

    def show_signals?
      @level >= 2
    end

    def show_methods?
      @level >= 3
    end

    def constant_line(node)
      lhs = node_source(node.children[0])
      name = node.children[1]
      rhs = node.children[2]
      target = lhs.nil? || lhs.empty? || lhs == 'nil' ? name.to_s : "#{lhs}::#{name}"
      rhs ? "#{target} = #{compact_value(rhs)}" : target
    end

    def attribute_line(node)
      method_name, = captures_for('(send nil $_ ...)', node)
      args = direct_symbol_arguments(node).map { |symbol| ":#{symbol}" }
      "#{method_name} #{args.join(', ')}"
    end

    def required_path(node)
      path_node = captures_for('(send nil $_ $(str _))', node).last
      path_node.children.first.inspect
    end

    def scope_line(node)
      name = captures_for('(send nil :scope (sym $_) ...)', node).first
      lambda_node = captures_for('(send nil :scope (sym _) $({lambda block} ... ...))', node).first
      args = lambda_args(lambda_node)
      [name, args].join
    end

    def captures_for(pattern, node)
      Fast.match?(pattern, node) || []
    end

    def lambda_args(node)
      return '' unless Fast.ast_node?(node)
      return '' unless node.type == :lambda || node.type == :block

      args_node =
        if node.type == :block
          node.children.find { |child| Fast.match?('(args ...)', child) }
        else
          node.children[0]
        end
      return '' unless Fast.match?('(args ...)', args_node) || Fast.match?('(args)', args_node)
      return '' if args_node.children.empty?

      "(#{args_node.children.map { |arg| node_source(arg) }.join(', ')})"
    end

    def direct_symbol_arguments(node)
      node.children.drop(2).filter_map do |child|
        captures = captures_for('(sym $_)', child)
        captures.first if captures.any?
      end
    end

    def method_signature(node)
      args = args_signature(node.children[1])
      "def #{node.children[0]}#{args}"
    end

    def singleton_method_signature(node)
      receiver = node_source(node.children[0])
      args = args_signature(node.children[2])
      "def #{receiver}.#{node.children[1]}#{args}"
    end

    def args_signature(args_node)
      return '' unless Fast.match?('(args ...)', args_node) || Fast.match?('(args)', args_node)
      return '' if args_node.children.empty?

      "(#{args_node.children.map { |arg| node_source(arg) }.join(', ')})"
    end

    def compact_value(node)
      return node_source(node) unless Fast.ast_node?(node)

      case node.type
      when :array
        '[...]'
      when :hash
        '{...}'
      when :block, :lambda
        '{ ... }'
      when :send
        return compact_value(node.children[0]) if node.children[1] == :freeze && node.children.length == 2

        node_source(node)
      else
        node_source(node)
      end
    end

    def node_source(node)
      return node.to_s unless Fast.ast_node?(node)

      node.loc.expression.source
    rescue StandardError
      node.to_s
    end

    def compact_node_source(node)
      source = node_source(node)
      return source unless source.include?("\n")

      head = source.lines.first.strip
      if head.end_with?('do') || head.include?(' do')
        "#{head} ... end"
      else
        "#{head} ..."
      end
    end

    def print_requires(requires, indent)
      return if requires.empty?

      formatted = requires.map { |entry| entry.split(' ', 2).last }.join(', ')
      puts "#{indent}requires: #{formatted}"
      puts
    end

    def print_lines(lines, indent)
      return if lines.empty?

      puts
      lines.each { |line| puts "#{indent}#{line}" }
    end

    def print_section(title, lines, indent)
      return if lines.empty?

      puts
      joined = lines.join(', ')
      if lines.one? || joined.length <= 100
        puts "#{indent}#{title}: #{joined}"
      else
        puts "#{indent}#{title}:"
        lines.each { |line| puts "#{indent}  #{line}" }
      end
    end

    def print_methods(methods, indent)
      VISIBILITIES.each do |visibility|
        next if methods[visibility].empty?

        puts
        puts "#{indent}#{visibility}" unless visibility == :public
        methods[visibility].each { |signature| puts "#{indent}#{'  ' unless visibility == :public}#{signature}" }
      end
    end
  end
end
