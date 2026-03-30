# frozen_string_literal: true

# For Rails code using deprecated `update_attributes` it uses `update` instead.
Fast.experiment('Rails/ReplaceUpdateAttributesWithUpdate') do
  lookup 'spec'
  # Search for any method call named update_attributes
  search '(send _ :update_attributes ...)'
  edit { |node| replace(node.loc.selector, 'update') }
  policy { |new_file| system("bundle exec rspec --fail-fast #{new_file}") }
end
