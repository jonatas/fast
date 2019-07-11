# frozen_string_literal: true

require 'spec_helper'
require 'fast/cli'

RSpec.describe Fast::Cli do
  def highlight(output)
    CodeRay.scan(output, :ruby).term
  end

  describe '.initialize' do
    subject(:cli) { described_class.new args }

    context 'with expression and file' do
      let(:args) { %w[def lib/fast.rb] }

      its(:pattern) { is_expected.to eq('def') }

      its(:files) { is_expected.to eq(['lib/fast.rb']) }
    end

    context 'with expression and folders' do
      let(:args) { %w[def lib/fast spec/fast] }

      its(:pattern) { is_expected.to eq('def') }

      its(:files) do
        is_expected.to include('lib/fast/cli.rb')
        is_expected.to include('spec/fast/cli_spec.rb')
      end
    end

    context 'with expression and file' do
      let(:args) { %w[match? lib/fast.rb -c] }

      its(:pattern) { is_expected.to eq('(send nil :match?)') }
      its(:files) { is_expected.to eq(['lib/fast.rb']) }
    end

    context 'with --pry' do
      let(:args) { %w[--pry] }

      its(:pry) { is_expected.to be_truthy }
    end

    context 'with --debug' do
      let(:args) { %w[--debug] }

      it { is_expected.to be_debug_mode }
    end

    context 'with --similar' do
      let(:args) { %w[1.1 --similar] }

      its(:similar) { is_expected.to be_truthy }
      its(:pattern) { is_expected.to eq('(float _)') }
    end

    context 'with --ast' do
      let(:args) { %w[--ast] }

      its(:show_sexp) { is_expected.to be_truthy }
    end

    context 'with --code' do
      let(:args) { %w[1.1 --code] }

      its(:from_code) { is_expected.to be_truthy }
      its(:pattern) { is_expected.to eq('(float 1.1)') }
    end

    context 'with --version' do
      let(:args) { %w[--version] }

      it do
        expect { cli.run! }.to output(Fast::VERSION.to_s + "\n").to_stdout
          .and raise_error SystemExit
      end
    end

    shared_examples_for 'show help' do
      it { expect { cli.run! }.to output(/Usage: /).to_stdout }
    end

    context 'with --help' do
      let(:args) { %w[--h] }

      it_behaves_like 'show help'
    end

    context 'without arguments' do
      let(:args) { %w[--h] }

      it_behaves_like 'show help'
    end

    context 'with search in file' do
      let(:args) { %w[casgn lib/fast/version.rb] }

      it 'prints file with line number' do
        expect { cli.run! }.to output(highlight(<<~RUBY)).to_stdout
          # lib/fast/version.rb:4
          VERSION = '#{Fast::VERSION}'
        RUBY
      end

      context 'with args to print ast' do
        let(:args) { %w[casgn lib/fast/version.rb --ast] }

        it 'prints ast instead of source code' do
          expect { cli.run! }.to output(highlight(<<~RUBY)).to_stdout
            # lib/fast/version.rb:4
            (casgn nil :VERSION
              (str "#{Fast::VERSION}"))
          RUBY
        end
      end

      context 'with args --headless --captures' do
        let(:args) { ['(casgn nil _ (str $_))', 'lib/fast/version.rb', '--captures', '--headless'] }

        it 'prints only captured scope' do
          expect { cli.run! }.to output(highlight(Fast::VERSION + "\n")).to_stdout
        end
      end
    end
  end

  describe 'Fast.highlight' do
    it 'uses coderay to make ruby syntax highlight' do
      out = instance_double('term')
      allow(out).to receive(:term)
      allow(CodeRay).to receive(:scan).with(:symbol, :ruby).and_return(out)
      Fast.highlight(:symbol)
    end
  end

  describe 'Fast.report' do
    let(:ast) { Fast.ast('a = 1') }

    it 'highlight the code with file in the header' do
      allow(Fast).to receive(:highlight).with('# some_file.rb:1').and_call_original
      allow(Fast).to receive(:highlight).with(ast, show_sexp: false).and_call_original
      expect { Fast.report(ast, file: 'some_file.rb', show_sexp: false) }
        .to output(highlight("# some_file.rb:1\na = 1\n")).to_stdout
    end

    context 'with headless option' do
      it 'highlight the code without the file printed in the header' do
        expect { Fast.report(ast, file: 'some_file.rb', headless: true) }
          .to output(highlight("a = 1\n")).to_stdout
      end
    end
  end
end
