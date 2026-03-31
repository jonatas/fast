# frozen_string_literal: true

require 'spec_helper'
require 'fast/git'

RSpec.describe Fast::Node do
  subject(:node) do
    Fast.ast_from_file('lib/fast.rb')
  end

  it { expect(node).to be_a(Fast::Node) }

  it 'keeps value equality with identical nodes' do
    expect(Fast::Node.new(:send, [nil, :call])).to eq(Fast::Node.new(:send, [nil, :call]))
    expect(Fast::Node.new(:send, [nil, :call]).hash).to eq(Fast::Node.new(:send, [nil, :call]).hash)
  end

  it 'supports updated nodes without mutating the original' do
    original = Fast::Node.new(:send, [nil, :call])
    updated = original.updated(:send, [nil, :other_call])

    expect(original.children).to eq([nil, :call])
    expect(updated.children).to eq([nil, :other_call])
  end

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
      expect(node.capture('(casgn nil $_)'))
        .to include(:TOKENIZER)
    end
  end

  unless ENV['TRAVIS']
    describe 'git extensions' do
      it 'allows to use git from AST nodes directly' do
        expect(node.git_blob).to be_an(Git::Object::Blob)
        expect(node.git_log).to be_an(Git::Log)
        expect(node.last_commit).to be_an(Git::Object::Commit)
      end

      it 'provides methods to get links from code' do
        expect(node.link)
          .to match(%r{https://github.com/jonatas/fast/blob/master/lib/fast.rb#L\d+-L\d+})

        expect(node.permalink)
          .to match(%r{https://github.com/jonatas/fast/blob/[0-9a-f]{40}/lib/fast.rb#L\d+-L\d+})

        expect(node.capture('(class $_ (const nil Find))').first.md_link)
          .to match(%r{\[FindString\]\(https://github.com/jonatas/fast/blob/master/lib/fast.rb#L\d+\)})
      end
    end
  end
end
