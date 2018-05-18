# frozen_string_literal: true

# Experimentally remove a before or an after block
Fast.experiment('RSpec/RemoveUselessBeforeAfterHook') do
  lookup 'spec'
  search '(block (send nil {before after}))'
  edit { |node| remove(node.loc.expression) }
  policy { |new_file| system("bin/spring rspec --fail-fast #{new_file}") }
end
