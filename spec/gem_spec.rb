# frozen_string_literal: true

require 'fast'

RSpec.describe 'Gem Audit' do
  let(:gemspec_path) { 'fast.gemspec' }
  let(:gemspec_ast) { Fast.ast_from_file(gemspec_path) }

  # This pattern finds the array assigned to spec.files
  let(:files_pattern) { '(send (lvar :spec) :files= (array ...))' }

  let(:included_files) do
    # Find the array node assigned to spec.files
    assignment = Fast.search_file('(send (lvar :spec) :files= (array ...))', gemspec_path).first
    expect(assignment).not_to be_nil, "Could not find spec.files assignment in gemspec"
    array_node = assignment.children.last
    # Capture all string literals inside the array
    Fast.capture('(str $_)', array_node)
  end

  it 'explicitly includes all ruby files from lib/' do
    lib_files = Dir['lib/**/*.rb']
    lib_files.each do |file|
      expect(included_files).to include(file), "File #{file} is in lib/ but missing from fast.gemspec static list"
    end
  end

  it 'explicitly includes all executables from bin/' do
    bin_files = Dir['bin/*']
    bin_files.each do |file|
      expect(included_files).to include(file), "File #{file} is in bin/ but missing from fast.gemspec static list"
    end
  end

  it 'does not include any forbidden development files' do
    forbidden_files = %w[.github .travis .rspec .rubocop Gemfile Rakefile Guardfile spec test experiments examples docs site ideia_blog_post.md]
    included_files.each do |file|
      forbidden_files.each do |forbidden|
        expect(file).not_to start_with(forbidden), "Forbidden file or directory included: #{file}"
      end
    end
  end

  it 'is a truly static list (verified by AST)' do
    # Find the array node assigned to spec.files
    assignment = Fast.search_file('(send (lvar :spec) :files= (array ...))', gemspec_path).first
    expect(assignment).not_to be_nil
    array_node = assignment.children.last
    # Check if any child of the array is a dynamic call instead of a string
    dynamic_calls = Fast.search('(send ...)', array_node)
    expect(dynamic_calls).to be_empty, "The spec.files list should be static, but found dynamic call: #{dynamic_calls.inspect}"
  end
end
