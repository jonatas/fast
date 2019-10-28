# frozen_string_literal: true

require 'spec_helper'
require 'fast/shortcut'

describe Fast::Shortcut do
  context 'when the params are arguments' do
    subject(:shortcut) do
      Fast.shortcut(:match_methods, '(def match?)', 'lib/fast.rb')
    end

    its(:args) { is_expected.to eq(['(def match?)', 'lib/fast.rb']) }

    it 'records the search with right params in the #shortcuts' do
      is_expected.to be_an(described_class)
      is_expected.to eq(Fast.shortcuts[:match_methods])
      expect(Fast.shortcuts).to have_key(:match_methods)
    end
  end

  context 'when params include options' do
    subject(:shortcut) { Fast.shortcut(:match_methods, '-c', 'match?', 'lib/fast.rb') }

    its(:options) { is_expected.to eq(['-c']) }
    its(:params) { is_expected.to eq(['match?', 'lib/fast.rb']) }

    describe '#merge_args' do
      it 'mix args replacing the params' do
        expect(shortcut.merge_args('lib')).to eq(%w[match? -c lib])
      end
    end
  end

  context 'when a block is given' do
    subject(:bump) do
      Fast.shortcut :bump_version do
        rewrite_file('(casgn nil VERSION (str _)', 'sample_version.rb') do |node|
          target = node.children.last.loc.expression
          replace(target, '0.0.2'.inspect)
        end
      end
    end

    before do
      File.open('sample_version.rb', 'w+') do |file|
        file.puts <<~RUBY
          module Something
            VERSION = "0.0.1"
          end
        RUBY
      end
    end

    after do
      File.delete('sample_version.rb')
    end

    describe '#run' do
      specify do
        expect do
          bump.run
        end.to change { IO.read('sample_version.rb') }.to(<<~RUBY)
          module Something
            VERSION = "0.0.2"
          end
        RUBY
      end
    end
  end
end
