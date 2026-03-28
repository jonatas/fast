# frozen_string_literal: true

require 'parser'

module Fast
  module ParserCompat
    VERSIONED_PARSER_RANGE = ((1..3).flat_map { |major| (0..9).map { |minor| [major, minor] } }).freeze

    class Builder < Parser::Builders::Default
      def n(type, children, source_map)
        Fast::Node.new(type, children, location: source_map)
      end
    end

    module_function

    def parse(content, buffer_name: '(string)')
      buffer = Fast::Source.parser_buffer(buffer_name, source: content)
      parser_class.new(builder).parse(buffer)
    rescue Parser::SyntaxError => e
      raise Fast::SyntaxError, e.message
    end

    def validate!(content, buffer_name: '(string)')
      buffer = Fast::Source.parser_buffer(buffer_name, source: content)
      parser = parser_class.new(builder)
      parser.diagnostics.all_errors_are_fatal = true
      parser.diagnostics.consumer = lambda do |diagnostic|
        message = Array(diagnostic.render).join("\n")
        raise Fast::SyntaxError, message
      end
      parser.parse(buffer)
      true
    end

    def builder
      require_parser!
      Builder.new
    end

    def parser_class
      require_parser!
      @parser_class ||= begin
        require parser_require_path
        Parser.const_get(parser_const_name)
      end
    end

    def parser_require_path
      "parser/#{parser_const_name.downcase}"
    end

    def parser_const_name
      @parser_const_name ||= begin
        current_version = Gem::Version.new(RUBY_VERSION[/\A\d+\.\d+/])

        VERSIONED_PARSER_RANGE
          .reverse
          .map { |major, minor| "Ruby#{major}#{minor}" }
          .find do |const_name|
            parser_version_supported?(const_name) &&
              Gem::Version.new(const_name.delete_prefix('Ruby').chars.join('.')) <= current_version
          end || raise(LoadError, "No parser implementation available for Ruby #{RUBY_VERSION}")
      end
    end

    def parser_version_supported?(const_name)
      require_parser!
      require "parser/#{const_name.downcase}"
      true
    rescue LoadError
      false
    end

    def reset_cache!
      remove_instance_variable(:@parser_class) if instance_variable_defined?(:@parser_class)
      remove_instance_variable(:@parser_const_name) if instance_variable_defined?(:@parser_const_name)
    end

    def require_parser!
      return if defined?(Parser::Builders::Default)

      require 'parser'
    end
  end
end
