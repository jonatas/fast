# frozen_string_literal: true

require 'spec_helper'
require 'fast/git'

RSpec.describe Fast::Node do
  subject(:node) do
    Fast.ast_from_file('lib/fast.rb')
  end

  it { expect(node).to be_a(Fast::Node) }

  it 'uses buffer name as file name' do
    expect(node.buffer_name).to eq('lib/fast.rb')
  end

  it 'allows to blame authors from range' do
    expect(node.blame_authors).to include('Jônatas Davi Paganini')
  end

  describe '#search' do
    it { expect(node.search('(class (const nil _) (const nil Find))').size > 10).to be_truthy }

    context 'with extra args' do
      it 'binds arguments in the expression' do
        expect(node.search('(%1 (const nil _) (const nil Find))', 'class').size > 10).to be_truthy
      end
    end
  end

  describe '#capture' do
    specify 'all inherited classes' do
      expect(node.capture('(casgn nil $_) (regexp _))'))
        .to include(:TOKENIZER)
    end
  end

  describe 'git extensions' do
    it 'allows to use git from AST directly' do
      unless ENV['TRAVIS']
        expect(node.git_blob).to be_an(Git::Object::Blob)
        expect(node.git_log).to be_an(Git::Log)
        expect(node.last_commit).to be_an(Git::Object::Commit)
      end
    end
  end
end
