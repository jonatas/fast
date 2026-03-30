# frozen_string_literal: true

# For Ruby code using deprecated `File.exists?` it uses `exist?` instead.
Fast.experiment('Ruby/ReplaceFileExistsWithExist') do
  lookup 'spec'
  search '(send (const nil :File) :exists? ...)'
  edit { |node| replace(node.loc.selector, 'exist?') }
  policy { |new_file| system("bundle exec rspec --fail-fast #{new_file}") }
end
