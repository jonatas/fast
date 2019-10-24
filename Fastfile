# frozen_string_literal: true

# Fastfile is loaded when you start an expression with a dot.
#
# You can introduce shortcuts or methods that can be embedded during your
# command line interactions with fast.
#
# Let's say you'd like to show the version that is over the version file
Fast.shortcut(:version, '(casgn nil VERSION (str _))', 'lib/fast/version.rb')

# You can run shortcuts appending a dot to the shortcut.
#   $ fast .version
#   # lib/fast/version.rb:4
#   VERSION = '0.1.2'

# Simple shortcut that I used often to show how the expression parser works
Fast.shortcut(:parser, '(class (const nil ExpressionParser)', 'lib/fast.rb')

# Use `fast .bump_version` to rewrite the version file
Fast.shortcut :bump_version do
  rewrite_file('lib/fast/version.rb', '(casgn nil VERSION (str _)') do |node|
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
