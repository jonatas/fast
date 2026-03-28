# frozen_string_literal: true

module Fast
  # Resume summarizes a Ruby file's structural elements into a shorter format
  class Resume
    def initialize(code_or_ast)
      @ast = code_or_ast.is_a?(String) ? Fast.ast(code_or_ast) : code_or_ast
    end

    def summarize
      evaluate(@ast)
    end

    private

    def evaluate(node, indent = '')
      return unless node.respond_to?(:type)

      case node.type
      when :module
        name = node.children[0].loc.expression.source
        puts "#{indent}module #{name}"
        evaluate(node.children[1], indent + '  ')
        puts "#{indent}end"
      when :class
        name = node.children[0].loc.expression.source
        parent = node.children[1] ? " < #{node.children[1].loc.expression.source}" : ''
        puts "#{indent}class #{name}#{parent}"
        body = node.children[2]
        summarize_class_body(body, indent + '  ') if body
        puts "#{indent}end"
      when :begin
        node.children.each { |c| evaluate(c, indent) }
      else
        summarize_class_body(node, indent)
      end
    end

    def summarize_class_body(body, indent)
      nodes = body.type == :begin ? body.children : [body]
      
      rels, attrs, scopes, hooks, validates, custom_validates, methods = partition_nodes(nodes)
      
      validated_fields = extract_validated_fields(validates)

      print_relationships(rels, indent)
      print_attributes(attrs, validated_fields, indent)
      print_scopes(scopes, indent)
      print_hooks(hooks, indent)
      print_validations(validates, custom_validates, indent)
      print_methods(methods, indent)
    end

    def partition_nodes(nodes)
      rels, attrs, scopes, hooks, validates, custom_validates, methods = [], [], [], [], [], [], []

      nodes.each do |n|
        next unless n.is_a?(Parser::AST::Node)
        
        if n.type == :def || n.type == :defs
          methods << n
        elsif n.type == :send && n.children[0].nil?
          categorize_send_node(n, rels, attrs, scopes, hooks, validates, custom_validates)
        end
      end
      [rels, attrs, scopes, hooks, validates, custom_validates, methods]
    end

    def categorize_send_node(n, rels, attrs, scopes, hooks, validates, custom_validates)
      method_name = n.children[1]
      if [:has_many, :belongs_to, :has_one, :has_and_belongs_to_many].include?(method_name)
        rels << n
      elsif [:attr_accessor, :attr_reader, :attr_writer].include?(method_name)
        attrs << n
      elsif method_name == :scope
        scopes << n
      elsif method_name.to_s.start_with?('before_') || method_name.to_s.start_with?('after_') || method_name.to_s.start_with?('around_')
        hooks << n
      elsif method_name == :validates
        validates << n
      elsif method_name == :validate
        custom_validates << n
      end
    end

    def extract_validated_fields(validates)
      validates.flat_map do |v|
        v.children[2..-1].select { |a| a.type == :sym }.map { |a| a.children[0] }
      end.compact
    end

    def print_relationships(rels, indent)
      rels.each { |r| puts "#{indent}#{r.loc.expression.source}" }
    end

    def print_attributes(attrs, validated_fields, indent)
      attrs.each do |a| 
        src = a.children[2..-1].map do |arg|
          if arg.type == :sym
            f = arg.children[0]
            validated_fields.include?(f) ? ":*#{f}" : ":#{f}"
          else
            arg.loc.expression.source
          end
        end.join(', ')
        puts "\n" if attrs.first == a
        puts "#{indent}#{a.children[1]} #{src}"
      end
    end

    def print_scopes(scopes, indent)
      return if scopes.empty?
      
      names = scopes.map do |s|
        name = s.children[2].children[0]
        lam = s.children[3]
        if lam && lam.type == :block
          args = (lam.children[1].loc.expression.source rescue '')
          "#{name}#{args}"
        else
          "#{name}"
        end
      end
      puts "\n#{indent}Scopes: #{names.join(', ')}"
    end

    def print_hooks(hooks, indent)
      return if hooks.empty?
      
      names = hooks.map do |h|
        params = h.children[2..].map { |a| (a.loc.expression.source rescue '') }.join(', ')
        "#{h.children[1]} #{params}".strip
      end
      puts "\n#{indent}Hooks: #{names.join(', ')}"
    end

    def print_validations(validates, custom_validates, indent)
      return if validates.empty? && custom_validates.empty?
      
      all_v = validates.map do |v| 
        v.children[2..-1].select { |a| a.type == :sym }.map { |a| "*#{a.children[0]}" }.join(', ')
      end
      all_v += custom_validates.map { |v| v.children[2..-1].map { |a| (a.loc.expression.source rescue '') }.join(', ') }
      
      merged = all_v.reject(&:empty?).join(', ')
      puts "\n#{indent}Validations: #{merged}" unless merged.empty?
    end

    def print_methods(methods, indent)
      puts "\n" if methods.any?
      methods.each do |m|
        if m.type == :def
          args = (m.children[1].loc.expression.source rescue '')
          args = "(#{args})" unless args.start_with?('(') || args.empty?
          puts "#{indent}def #{m.children[0]}#{args}"
        else
          args = (m.children[2].loc.expression.source rescue '')
          args = "(#{args})" unless args.start_with?('(') || args.empty?
          puts "#{indent}def self.#{m.children[1]}#{args}"
        end
      end
    end
  end
end
