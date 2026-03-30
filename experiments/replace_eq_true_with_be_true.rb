# frozen_string_literal: true

# For RSpec tests using `expect(x).to eq(true)` it tries to use `be(true)` instead.
Fast.experiment('RSpec/ReplaceEqTrueWithBeTrue') do
  lookup 'spec'
  search '(send nil :eq (true))'
  edit { |node| replace(node.loc.selector, 'be') }
  policy { |new_file| system("bundle exec rspec --fail-fast #{new_file}") }
end
