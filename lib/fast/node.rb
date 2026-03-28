# frozen_string_literal: true

module Fast
  class Node < Parser::AST::Node
    def initialize(type, children = [], properties = {})
      super
      assign_parents!
    end

    class << self
      def set_parent(node, parent)
        NODE_PARENTS[node] = parent
      end

      def parent_for(node)
        NODE_PARENTS[node]
      end
    end

    # @return [String] with path of the file or simply buffer name.
    def buffer_name
      expression.source_buffer.name
    end

    # @return [Fast::Source::Range] from the expression
    def expression
      loc.expression
    end

    # Backward-compatible alias for callers that still use `location`.
    def location
      loc
    end

    # @return [String] with the content of the #expression
    def source
      expression.source
    end

    # @return [Boolean] true if a file exists with the #buffer_name
    def from_file?
      File.exist?(buffer_name)
    end

    def each_child_node
      return enum_for(:each_child_node) unless block_given?

      children.select { |child| Fast.ast_node?(child) }.each { |child| yield child }
    end

    def each_descendant(*types, &block)
      return enum_for(:each_descendant, *types) unless block_given?

      each_child_node do |child|
        yield child if types.empty? || types.include?(child.type)
        child.each_descendant(*types, &block) if child.respond_to?(:each_descendant)
      end
    end

    def root?
      parent.nil?
    end

    def parent
      self.class.parent_for(self)
    end

    def updated(type = nil, children = nil, properties = nil)
      updated_node = super
      updated_node.send(:assign_parents!)
      updated_node
    end

    def to_a
      children.dup
    end

    def deconstruct
      to_a
    end

    def to_ast
      self
    end

    def to_sexp
      format_node(:sexp)
    end

    def to_s
      to_sexp
    end

    def inspect
      format_node(:inspect)
    end

    def respond_to_missing?(method_name, include_private = false)
      type_query_method?(method_name) || super
    end

    def method_missing(method_name, *args, &block)
      return type == type_query_name(method_name) if type_query_method?(method_name) && args.empty? && !block

      super
    end

    # @return [Array<String>] with authors from the current expression range
    def blame_authors
      `git blame -L #{expression.first_line},#{expression.last_line} #{buffer_name}`.lines.map do |line|
        line.split('(')[1].split(/\d+/).first.strip
      end
    end

    # @return [String] with the first element from #blame_authors
    def author
      blame_authors.first
    end

    # Search recursively into a node and its children using a pattern.
    # @param [String] pattern
    # @param [Array] *args extra arguments to interpolate in the pattern.
    # @return [Array<Fast::Node>>] with files and results
    def search(pattern, *args)
      Fast.search(pattern, self, *args)
    end

    # Captures elements from search recursively
    # @param [String] pattern
    # @param [Array] *args extra arguments to interpolate in the pattern.
    # @return [Array<Fast::Node>>] with files and results
    def capture(pattern, *args)
      Fast.capture(pattern, self, *args)
    end

    private

    def assign_parents!
      each_child_node do |child|
        self.class.set_parent(child, self)
        child.send(:assign_parents!) if child.respond_to?(:assign_parents!, true)
      end
    end

    def type_query_method?(method_name)
      method_name.to_s.end_with?('_type?')
    end

    def type_query_name(method_name)
      method_name.to_s.delete_suffix('_type?').to_sym
    end

    def format_node(style)
      opener = style == :inspect ? "s(:#{type}" : "(#{type}"
      separator = style == :inspect ? ', ' : ' '
      inline_children = children.map { |child| format_atom(child, style, inline: true) }
      return "#{opener})" if inline_children.empty?

      if children.none? { |child| Fast.ast_node?(child) } && inline_children.all? { |child| !child.include?("\n") }
        return "#{opener}#{separator}#{inline_children.join(separator)})"
      end

      lines = [opener]
      current_line = +''

      children.each do |child|
        formatted = format_atom(child, style, inline: false)
        if formatted.include?("\n")
          flush_current_line!(lines, current_line, style)
          current_line.clear
          lines << indent_multiline(formatted)
        elsif Fast.ast_node?(child)
          flush_current_line!(lines, current_line, style)
          current_line = formatted.dup
        else
          current_line << separator unless current_line.empty?
          current_line << formatted
        end
      end

      flush_current_line!(lines, current_line, style)
      if lines.length > 2 && scalar_line?(lines[1], style)
        lines[0] = "#{lines[0]}#{separator}#{lines[1].strip}"
        lines.delete_at(1)
      end
      lines[-1] = "#{lines[-1]})"
      lines.join("\n")
    end

    def flush_current_line!(lines, current_line, style)
      return if current_line.empty?

      line = style == :inspect ? "  #{current_line}," : "  #{current_line}"
      lines << line
    end

    def indent_multiline(text)
      text.lines.map { |line| "  #{line}" }.join
    end

    def format_atom(atom, style, inline:)
      if Fast.ast_node?(atom)
        text = style == :inspect ? atom.inspect : atom.to_sexp
        return text if inline || !text.include?("\n")

        style == :inspect ? trim_trailing_comma(text) : text
      else
        format_scalar(atom, style)
      end
    end

    def trim_trailing_comma(text)
      lines = text.lines
      lines[-1] = lines[-1].sub(/,\z/, '')
      lines.join
    end

    def scalar_line?(line, style)
      stripped = line.strip
      return false if stripped.empty?

      opener = style == :inspect ? 's(' : '('
      !stripped.start_with?(opener)
    end

    def format_scalar(value, _style)
      case value
      when Symbol, String
        value.inspect
      when Array
        "[#{value.map { |item| format_atom(item, :sexp, inline: true) }.join(', ')}]"
      else
        value.inspect
      end
    end
  end
end
