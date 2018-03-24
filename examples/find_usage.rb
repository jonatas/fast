#!/usr/bin/env ruby
# frozen_string_literal: true

# List files that matches with some expression
# Usage:
#
# ruby examples/find_usage.rb defs
#
# Or be explicit about directory or folder:
#
# ruby examples/find_usage.rb defs lib/
$LOAD_PATH.unshift(File.expand_path('lib', __dir__))

require 'fast'
require 'coderay'

arguments = ARGV
pattern = arguments.shift
files = Fast.ruby_files_from(arguments.any? ? arguments : '.')
files.select do |file|
  begin
    puts file if Fast.search_file(pattern, file).any?
  rescue Parser::SyntaxError
    []
  end
end
