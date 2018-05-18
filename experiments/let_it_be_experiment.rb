# frozen_string_literal: true

# For specs using `let!(:something) { create ... }` it tries to use `let_it_be` instead
Fast.experiment('RSpec/LetItBe') do
  lookup 'spec'
  search '(block $(send nil let! (sym _)) (args) (send nil create))'
  edit { |_, (let)| replace(let.loc.selector, 'let_it_be') }
  policy { |new_file| system("bin/spring rspec --fail-fast #{new_file}") }
end
