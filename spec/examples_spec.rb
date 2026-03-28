# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'tmpdir'

RSpec.describe 'example scripts' do
  let(:ruby) { RbConfig.ruby }
  let(:repo_root) { File.expand_path('..', __dir__) }

  def run_example(script, *args)
    Open3.capture3({ 'RUBYOPT' => nil }, ruby, script, *args, chdir: repo_root)
  end

  it 'runs simple_rewriter' do
    stdout, stderr, status = run_example('examples/simple_rewriter.rb')

    expect(status.success?).to be(true), stderr
    expect(stdout).to eq("variable_renamed = 1\n")
  end

  it 'accepts directories in method_complexity' do
    stdout, stderr, status = run_example('examples/method_complexity.rb', 'lib')

    expect(status.success?).to be(true), stderr
    expect(stdout).to include('| Method | Complexity |')
  end

  it 'handles empty similarity results without crashing' do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'sample.rb'), "class Sample\n  def call\n    1\n  end\nend\n")

      stdout, stderr, status = run_example('examples/similarity_research.rb', 'def', dir)

      expect(status.success?).to be(true), stderr
      expect(stdout).to include('No similarities found.')
    end
  end
end
