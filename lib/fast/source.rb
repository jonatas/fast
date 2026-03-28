# frozen_string_literal: true

module Fast
  module Source
    class Buffer
      attr_accessor :source
      attr_reader :name

      def initialize(name, source: nil)
        @name = name
        @source = source
      end

      def source_range(begin_pos = 0, end_pos = source.to_s.length)
        Fast::Source.range(self, begin_pos, end_pos)
      end
    end

    class Range
      attr_reader :begin_pos, :end_pos, :source_buffer

      def initialize(source_buffer, begin_pos, end_pos)
        @source_buffer = source_buffer
        @begin_pos = begin_pos
        @end_pos = end_pos
      end

      def begin
        self.class.new(source_buffer, begin_pos, begin_pos)
      end

      def end
        self.class.new(source_buffer, end_pos, end_pos)
      end

      def source
        source_buffer.source.to_s[begin_pos...end_pos]
      end

      def line
        first_line
      end

      def first_line
        source_buffer.source.to_s[0...begin_pos].count("\n") + 1
      end

      def last_line
        source_buffer.source.to_s[0...end_pos].count("\n") + 1
      end

      def column
        last_newline = source_buffer.source.to_s.rindex("\n", begin_pos - 1)
        begin_pos - (last_newline ? last_newline + 1 : 0)
      end

      def to_range
        begin_pos...end_pos
      end

      def join(other)
        self.class.new(source_buffer, [begin_pos, other.begin_pos].min, [end_pos, other.end_pos].max)
      end

      def adjust(begin_pos: 0, end_pos: 0)
        self.class.new(source_buffer, self.begin_pos + begin_pos, self.end_pos + end_pos)
      end
    end

    class Map
      attr_accessor :expression, :node

      def initialize(expression)
        @expression = expression
      end

      def begin
        expression.begin_pos
      end

      def end
        expression.end_pos
      end

      def with_expression(new_expression)
        duplicate_with(expression: new_expression)
      end

      def with_operator(operator)
        duplicate_with(operator: operator)
      end

      private

      def duplicate_with(overrides = {})
        copy = dup
        overrides.each { |name, value| copy.instance_variable_set(:"@#{name}", value) }
        copy
      end
    end

    module_function

    def parser_buffer(name, source: nil)
      require 'parser'

      buffer = Parser::Source::Buffer.new(name)
      buffer.source = source if source
      buffer
    end

    def buffer(name, source: nil, buffer_class: Fast::Source::Buffer)
      buffer_class.new(name, source: source)
    end

    def range(buffer, start_pos, end_pos)
      Fast::Source::Range.new(buffer, start_pos, end_pos)
    end

    def map(expression)
      Fast::Source::Map.new(expression)
    end
  end
end
