# frozen_string_literal: true

require 'spec_helper'
require 'fast/cli'
require 'fast/shortcut'

RSpec.describe Fast::Cli do
  def highlight(output)
    CodeRay.scan(output, :ruby).term
  end

  describe '.initialize' do
    subject(:cli) { described_class.new args }

    context 'with expression and file' do
      let(:args) { %w[def lib/fast.rb] }

      its(:pattern) { is_expected.to eq('def') }
    end

    context 'with expression and folders' do
      let(:args) { %w[def lib/fast spec/fast] }

      its(:pattern) { is_expected.to eq('def') }
    end

    context 'with --sql to search from sql' do
      include_context 'with sql file'
      let(:sql) { 'SELECT * FROM customers' }
      let(:args) { ['--no-color', '--sql', "(relname 'customers')", file] }

      specify do
        expect { cli.run! }.to output(<<~OUT).to_stdout
          # tmp.sql:1
          customers
        OUT
      end

      context 'with --sql --from-code' do
        let(:args) { %w[--no-color --sql --from-code] + ['table customers', file] }

        specify do
          expect { cli.run! }.to output(<<~OUT).to_stdout
            # tmp.sql:1
            SELECT * FROM customers
          OUT
        end

        context 'when showing AST' do
          let(:args) { %w[--no-color --sql --from-code --ast] + ['select id from users'] }

          it 'displays AST with underscores instead of hyphens' do
            expect { cli.run! }.to output(/\(select_stmt\n.*target_list\n.*res_target/).to_stdout
            expect { cli.run! }.not_to output(/select-stmt|target-list|res-target/).to_stdout
          end
        end

        context 'when searching in files' do
          let(:sql_content) { 'SELECT * FROM customers' }
          let(:args) { %w[--no-color --sql --from-code] + ['select * from users', file] }

          before do
            File.write(file, sql_content)
          end

          it 'finds matching SQL statements' do
            expect { cli.run! }.to output("# tmp.sql:1\n#{sql_content}\n").to_stdout
          end
        end
      end
    end

    context 'with --from-code for Ruby' do
      context 'when showing AST' do
        let(:args) { %w[--no-color --from-code --ast] + ['def hello; end'] }

        it 'displays the Ruby AST' do
          expect { cli.run! }.to output(/(def :hello\n?\s+\(args\))/).to_stdout
        end
      end

      context 'when searching in files' do
        let(:ruby_file) { 'test.rb' }
        let(:ruby_content) { "def hello\n  puts 'world'\nend" }
        let(:args) { %w[--no-color --from-code] + ['def hello', ruby_file] }

        before do
          File.write(ruby_file, ruby_content)
        end

        after do
          File.unlink(ruby_file) if File.exist?(ruby_file)
        end

        it 'finds matching Ruby code' do
          expect { cli.run! }.to output(/# test.rb:1\n#{ruby_content}/).to_stdout
        end
      end
    end

    context 'with --pry' do
      let(:args) { %w[--pry] }

      its(:pry) { is_expected.to be_truthy }
    end

    context 'with --parallel' do
      let(:args) { %w[--parallel] }

      it { is_expected.to be_parallel }

      context 'with -p as shortcut' do
        let(:args) { %w[-p] }

        it { is_expected.to be_parallel }
      end

      context 'with -p and --pry' do
        let(:args) { %w[--parallel --pry] }

        it 'raises incompatible error' do
          expect { cli.run! }.to raise_error(RuntimeError, 'pry and parallel options are incompatible :(')
        end
      end
    end

    context 'with --debug' do
      let(:args) { %w[--debug] }

      it { is_expected.to be_debug_mode }
    end

    context 'with --similar' do
      let(:args) { %w[--ast --similar 1.1] }

      its(:similar) { is_expected.to be_truthy }

      specify do
        cli.run!
        expect(cli.pattern).to eq('(float _)')
      end
    end

    context 'with --ast' do
      let(:args) { %w[--ast] }

      its(:show_sexp) { is_expected.to be_truthy }
    end

    context 'with --ast --from-code ' do
      let(:args) { %w[--no-color --ast --from-code match?] }

      specify do
        expect { cli.run! }.to output(/(send nil :match?)/).to_stdout
      end
    end

    context 'with --version' do
      let(:args) { %w[--version] }

      it do
        expect { cli.run! }.to output("#{Fast::VERSION}\n").to_stdout
          .and raise_error SystemExit
      end
    end

    shared_examples_for 'show help' do
      it { expect { cli.run! }.to output(/Usage: /).to_stdout }
    end

    context 'with --help' do
      let(:args) { %w[--help] }

      it_behaves_like 'show help'
    end

    context 'without arguments' do
      let(:args) { %w[] }

      it_behaves_like 'show help'
    end

    context 'with search in file' do
      let(:args) { %w[casgn lib/fast/version.rb] }

      it 'prints file with line number' do
        expect { cli.run! }.to output(highlight(<<~RUBY)).to_stdout
          # lib/fast/version.rb:4
          \s\sVERSION = '#{Fast::VERSION}'
        RUBY
      end

      context 'when the code is not from the beginning of the line' do
        let(:args) { %w[str lib/fast/version.rb] }

        it 'prints fragment of line' do
          cli.run!
          expect { cli.run! }.to output(highlight(<<~RUBY)).to_stdout
            # lib/fast/version.rb:4
            '#{Fast::VERSION}'
          RUBY
        end
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

      context 'with shortcut' do
        let(:args) { ['.show_version'] }

        before do
          Fast.shortcuts.delete :show_version
          Fast.shortcut(:show_version, '(casgn nil _ (str _))', 'lib/fast/version.rb')
        end

        its(:pattern) { is_expected.to eq('(casgn nil _ (str _))') }

        it 'uses the predefined values from the shortcut' do
          expect { cli.run! }.to output(highlight(<<~RUBY)).to_stdout
            # lib/fast/version.rb:4
              VERSION = '#{Fast::VERSION}'
          RUBY
        end
      end

      context 'with args --headless --captures' do
        let(:args) { ['(casgn nil _ (str $_))', 'lib/fast/version.rb', '--captures', '--headless'] }

        it 'prints only captured scope' do
          expect { cli.run! }.to output("#{highlight(Fast::VERSION)}\n").to_stdout
        end
      end
    end
  end

  describe 'Fast.highlight' do
    let(:out) { instance_spy('TTY::Color::NoValue') }
    
    before do
      allow(out).to receive(:term)
      allow(CodeRay).to receive(:scan).with('symbol', :ruby).and_return(out)
    end

    it 'uses coderay to make ruby syntax highlight' do
      Fast.highlight(:symbol)
    end
  end

  describe 'Fast.report' do
    let(:ast) { Fast.ast('a = 1') }

    it 'highlight the code with file in the header' do
      allow(Fast).to receive(:highlight).with('# some_file.rb:1', colorize: true).and_call_original
      allow(Fast).to receive(:highlight).with(ast, show_sexp: false, colorize: true).and_call_original
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
