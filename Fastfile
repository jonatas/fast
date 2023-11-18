# frozen_string_literal: true
# Fastfile is loaded when you start an expression with a dot.
#
# You can introduce shortcuts or methods that can be embedded during your
# command line interactions with fast.
#
# Let's say you'd like to show the version that is over the version file
version_file = Dir['lib/*/version.rb'].first
Fast.shortcut(:version, '(casgn nil VERSION (str _))', version_file)

# Show all classes that inherits Fast::Find
Fast.shortcut(:finders, '(class ... (const nil Find)', 'lib')

# You can run shortcuts appending a dot to the shortcut.
#   $ fast .version
#   # lib/fast/version.rb:4
#   VERSION = '0.1.2'

# Simple shortcut that I used often to show how the expression parser works
Fast.shortcut(:parser, '(class (const nil ExpressionParser)', 'lib/fast.rb')

# Use `fast .bump_version` to rewrite the version file
Fast.shortcut :bump_version do
  rewrite_file('(casgn nil VERSION (str _)', version_file) do |node|
    target = node.children.last.loc.expression
    pieces = target.source.split('.').map(&:to_i)
    pieces.reverse.each_with_index do |fragment, i|
      if fragment < 9
        pieces[-(i + 1)] = fragment + 1
        break
      else
        pieces[-(i + 1)] = 0
      end
    end
    replace(target, "'#{pieces.join('.')}'")
  end
end

# List all shortcut with comments
Fast.shortcut :shortcuts do
  fast_files.each do |file|
    lines = File.readlines(file).map { |line| line.chomp.gsub(/\s*#/, '').strip }
    result = capture_file('(send _ :shortcut $(sym _) ...)', file)
    result = [result] unless result.is_a? Array
    result.each do |capture|
      target = capture.loc.expression
      puts "fast .#{target.source[1..].ljust(30)} # #{lines[target.line - 2]}"
    end
  end
end

# Use to walkthrough the docs files with fast examples
# fast .intro
Fast.shortcut :intro do
  ARGV << File.join(File.dirname(__FILE__), 'docs', 'walkthrough.md')

  Fast.shortcuts[:walk].run
end

# Useful for `fast .walk file.md` but not required by the library.
private
def require_or_install_tty_md
  require 'tty-markdown'
rescue LoadError
  puts 'Installing tty-markdown gem to better engage you :)'
  Gem.install('tty-markdown')
  puts 'Done! Now, back to our topic \o/'
  system('clear')
  retry
end

# Interactive command line walkthrough
# fast .walk docs/walkthrough.md
Fast.shortcut :walk do
  require_or_install_tty_md
  file = ARGV.last
  execute = ->(line) { system(line) }
  walk = ->(line) { line.each_char { |c| sleep(0.02) and print(c) } }
  File.readlines(file).each do |line|
    case line
    when /^fast /
      walk[line]
      execute[line]
    when /^\$ /
      walk[line]
      execute[line[2..]]
    when /^!{3}\s/
      # Skip warnings that are only for web tutorials
    else
      walk[TTY::Markdown.parse(line)]
    end
  end
end

# Format SQL
Fast.shortcut :format_sql do
  require 'fast/sql'
  file = ARGV.last
  method = File.exist?(file) ? :parse_sql_file : :parse_sql
  ast = Fast.public_send(method, file)
  ast = ast.first if ast.is_a? Array

  output = Fast::SQL.replace('_', ast) do |root|
    sb = root.loc.expression.source_buffer
    sb.tokens.each do |token|
      if token.keyword_kind == :RESERVED_KEYWORD
        range = Parser::Source::Range.new(sb, token.start, token.end)
        replace(range, range.source.upcase)
      end
    end
  end
  require 'fast/cli'
  puts Fast.highlight(output, sql: true)
end
