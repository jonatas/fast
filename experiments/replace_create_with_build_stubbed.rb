# frozen_string_literal: true

# For specs using `let(:something) { create ... }` it tries to use
# `build_stubbed` instead
Fast.experiment('RSpec/ReplaceCreateWithBuildStubbed') do
  lookup 'spec'
  search '(block (send nil let (sym _)) (args) $(send nil create))'
  edit { |_, (create)| replace(create.loc.selector, 'build_stubbed') }
  policy { |new_file| system("bin/spring rspec --format progress --fail-fast #{new_file}") }
end
