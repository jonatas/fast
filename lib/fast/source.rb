# frozen_string_literal: true

require 'parser'

module Fast
  module Source
    parser_source = Parser.const_get(:Source)

    Buffer = Class.new(parser_source.const_get(:Buffer))
    Range = Class.new(parser_source.const_get(:Range))
    Map = Class.new(parser_source.const_get(:Map))

    module_function

    def buffer(name, source: nil, buffer_class: Fast::Source::Buffer)
      buffer = buffer_class.new(name)
      buffer.source = source if source
      buffer
    end

    def range(buffer, start_pos, end_pos)
      Fast::Source::Range.new(buffer, start_pos, end_pos)
    end

    def map(expression)
      Fast::Source::Map.new(expression)
    end
  end
end
