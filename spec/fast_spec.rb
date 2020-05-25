# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Fast do
  include RuboCop::AST::Sexp

  let(:code) { ->(string) { described_class.ast(string) } }

  describe '.match?' do
    context 'with `Fast.expressions`' do
      it { expect(described_class).to be_match('(...)', s(:int, 1)) }
      it { expect(described_class).to be_match('(_ _)', s(:int, 1)) }
      it { expect(described_class).to be_match('(int odd?)', s(:int, 1)) }
      it { expect(described_class).not_to be_match('(int even?)', s(:int, 1)) }
      it { expect(described_class).to be_match('(str "string")', code['"string"']) }
      it { expect(described_class).to be_match('(float 111.2345)', code['111.2345']) }
      it { expect(described_class).to be_match('(const nil? :I18n)', code['I18n']) }
    end

    it 'ignores empty spaces' do
      expect(described_class).to be_match(
        '(send    (send    (send   nil?   _)   _)   _)',
        s(:send, s(:send, s(:send, nil, :a), :b), :c)
      )
    end

    describe '`{}`' do
      it 'allows match `or` operator' do
        expect(described_class).to be_match('({int float} _)', code['1.2'])
      end

      it 'allows match first case' do
        expect(described_class).to be_match('({int float} _)', code['1'])
      end

      it 'return false if does not match' do
        expect(described_class).not_to be_match('({int float} _)', code['""'])
      end

      it 'works in nested levels' do
        expect(described_class).to be_match('(send ({int float} _) :+ (int _))', code['1.2 + 1'])
      end

      it 'works with complex operations nested levels' do
        expect(described_class).to be_match('(send ({int float} _) :+ (int _))', code['2 + 5'])
      end

      it 'does not match if the correct operator is missing' do
        expect(described_class).not_to be_match('(send ({int float} _) + (int _))', code['2 - 5'])
      end

      it 'matches with the correct operator' do
        expect(described_class).to be_match('(send ({int float} _) {:+ :-} (int _))', code['2 - 5'])
      end

      it 'matches multiple symbols' do
        expect(described_class).to be_match('(send {nil? _ } :b)', code['b'])
        expect(described_class).to be_match('(send {nil? _} :b)', code['a.b'])
      end
    end

    describe '`[]`' do
      it 'join expressions with `and`' do
        expect(described_class).to be_match('([!str !hash] _)', code['3'])
      end

      it 'allow join in any level' do
        expect(described_class).to be_match('(int [!1 !2])', code['3'])
      end
    end

    describe '`not` negates with !' do
      it { expect(described_class).to be_match('!(int _)', code['1.0']) }
      it { expect(described_class).not_to be_match('!(int _)', code['1']) }
      it { expect(described_class).to be_match('!({str int float} _)', code[':symbol']) }
      it { expect(described_class).not_to be_match('!({str int float} _)', code['1']) }
    end

    describe '`$` for capturing' do
      it 'last children' do
        expect(described_class.match?('(send nil? $...)', code['a'])).to eq([:a])
      end

      it 'the entire node' do
        expect(described_class.match?('$(int _)', s(:int, 1))).to eq(s(:int, 1))
      end

      it 'the value' do
        expect(described_class.match?('(sym $_)', s(:sym, :a))).to eq(:a)
      end

      it 'multiple nodes' do
        expect(described_class.match?('(send $(int _) :+ $(int _))', s(:send, s(:int, 1), :+, s(:int, 2)))).to eq([s(:int, 1), s(:int, 2)])
      end

      it 'specific children' do
        expect(described_class.match?('(send (int $_) :+ (int $_))', s(:send, s(:int, 1), :+, s(:int, 2)))).to eq([1, 2])
      end

      it 'complex negated joined condition' do
        expect(described_class.match?('$!({str int float} _)', s(:sym, :sym))).to eq(s(:sym, :sym))
      end

      describe 'capture method' do
        let(:ast) { code['def reverse_string(string) string.reverse end'] }

        it 'anonymously name' do
          expect(described_class.match?('(def $_ _ ...)', ast)).to eq(:reverse_string)
        end

        it 'static name' do
          expect(described_class.match?('(def $:reverse_string _ ...)', ast)).to eq(:reverse_string)
        end

        it 'parameter' do
          expect(described_class.match?('(def :reverse_string (args (arg $_)) ...)', ast)).to eq(:string)
        end

        it 'content' do
          expect(described_class.match?('(def :reverse_string (args (arg _)) $...)', ast)).to eq([s(:send, s(:lvar, :string), :reverse)])
        end
      end

      describe 'capture symbol in multiple conditions' do
        let(:expression) { '(send {nil? _} $_)' }

        it { expect(described_class.match?(expression, code['b'])).to eq(:b) }
        it { expect(described_class.match?(expression, code['a.b'])).to eq(:b) }
      end
    end

    describe '`Parent` can follow expression in children with `^`' do
      it 'ignores type and search in children using expression following' do
        expect(described_class).to be_match('`(int _)', code['a = 1'])
      end

      it 'captures parent of parent and also ignore non node children' do
        ast = code['b = a = 1']
        expect(described_class.match?('$``(int _)', ast)).to eq(ast)
      end
    end

    describe '%<argument-index> to bind an external argument into the expression' do
      it 'binds extra arguments into the expression' do
        expect(described_class).to be_match('(lvasgn %1 (int _))', code['a = 1'], :a)
        expect(described_class).to be_match('(str %1)', code['"test"'], 'test')
        expect(described_class).to be_match('(%1 %2)', code['"test"'], :str, 'test')
        expect(described_class).to be_match('(%1 %2)', code[':symbol'], :sym, :symbol)
        expect(described_class).to be_match('({%1 %2} _)', code[':symbol'], :str, :sym)
        expect(described_class).not_to be_match('(lvasgn %1 (int _))', code['a = 1'], :b)
        expect(described_class).not_to be_match('{%1 %2}', code['1'], :str, :sym)
      end
    end
  end

  describe '#search' do
    subject(:search) { described_class.search(pattern, node, *args) }

    let 'with extra args' do
      let(:args) { [:int, 1] }
      let(:node) { code['1'] }
      let(:pattern) { '(%1 %2)' }

      it 'binds arguments to the pattern' do
        expect(search).to eq([code['1']])
      end
    end

    context 'without extra args' do
      let(:args) { nil }
      let(:node) { code['1'] }
      let(:pattern) { '(int 1)' }

      it { expect(search).to eq([code['1']]) }
    end
  end

  describe 'search in files' do
    before do
      File.open('sample.rb', 'w+') do |file|
        file.puts <<~RUBY
          # One new comment
          class SelfPromotion
            AUTHOR = "Jônatas Davi Paganini"
            def initialize(name, language='pt')
              @name = name
              @lang = language if LANGUAGES.include?(language)
            end
            def welcome
              case @lang
              when 'pt' then puts "Olá \#{@name}"
              when 'es' then puts "Hola \#{@name}"
              else puts "Hello \#{@name}"
              end
            end
            def self.thanks
              welcome_message = new('friend', 'en')
              message = [AUTHOR, "wants to say", welcome_message]
              puts message.join(' ')
            end
          end
        RUBY
      end
    end

    after do
      File.delete('sample.rb')
    end

    it 'capture things flatten and unique nodes' do
      method_names = described_class.search_file('(def $_ _ ...)', 'sample.rb').grep(Symbol)
      expect(method_names).to eq(%i[initialize welcome])
    end

    it 'captures const symbol' do
      _, capture = described_class.search_file('(casgn nil? $_ ...)', 'sample.rb')
      expect(capture).to eq(:AUTHOR)
    end

    it 'captures const assignment values' do
      _, capture = described_class.search_file('(casgn nil? _ (str $_))', 'sample.rb')
      expect(capture).to eq('Jônatas Davi Paganini')
    end

    describe '.capture_file' do
      it 'captures puts arguments' do
        res = described_class.capture_file('(send nil? :puts $(dstr ...))', 'sample.rb')
        strings = res.map { |node| node.loc.expression.source }
        expect(strings).to eq(['"Olá #{@name}"', '"Hola #{@name}"', '"Hello #{@name}"'])
      end

      it 'capture dynamic strings into nodes' do
        res = described_class.capture_file('$(dstr ...)', 'sample.rb')
        strings = res.map { |node| node.loc.expression.source }
        expect(strings).to eq(['"Olá #{@name}"', '"Hola #{@name}"', '"Hello #{@name}"'])
      end

      it 'captures instance variables' do
        ivars = described_class.capture_file('(ivasgn $_ ...)', 'sample.rb')
        expect(ivars).to eq(%i[@name @lang])
      end

      it 'captures local variable nodes' do
        lvars = described_class.capture_file('(lvar $_)', 'sample.rb').uniq
        expect(lvars).to eq(%i[name language welcome_message message])
      end
    end
  end

  describe '.search_all' do
    it 'allow search multiple files in the same time' do
      results = described_class.search_all('(casgn nil? :VERSION ...)', ['lib/fast/version.rb'])
      expect(results).to have_key('lib/fast/version.rb')
      expect(results['lib/fast/version.rb'].map { |n| n.loc.expression.source }).to eq(["VERSION = '#{Fast::VERSION}'"])
    end

    context 'with empty file' do
      before { File.open('test-empty-file.rb', 'w+') { |f| f.puts '' } }

      after { File.delete('test-empty-file.rb') }

      it { expect(described_class.search_all('(casgn nil? :VERSION)', ['test-empty-file.rb'])).to be_nil }
    end
  end

  describe '.capture_all' do
    it 'allow search multiple files in the same time' do
      results = described_class.capture_all('(casgn nil? :VERSION (str $_))', ['lib/fast/version.rb'])
      expect(results).to eq('lib/fast/version.rb' => [Fast::VERSION])
    end

    context 'with empty file' do
      before { File.open('test-empty-file.rb', 'w+') { |f| f.puts '' } }

      after { File.delete('test-empty-file.rb') }

      it { expect(described_class.capture_all('(casgn nil? VERSION)', ['test-empty-file.rb'])).to be_nil }
    end
  end

  describe '.capture' do
    it 'single element' do
      expect(described_class.capture('(lvasgn _ (int $_))', code['a = 1'])).to eq(1)
    end

    it 'array elements' do
      expect(described_class.capture('(lvasgn $_ (int $_))', code['a = 1'])).to eq([:a, 1])
    end

    it 'nodes' do
      expect(described_class.capture('(lvasgn _ $(int _))', code['a = 1'])).to eq(code['1'])
    end

    it 'multiple nodes' do
      expect(described_class.capture('$(lvasgn _ (int _))', code['a = 1'])).to eq(code['a = 1'])
    end
  end

  describe '.ruby_files_from' do
    it 'captures ruby files from directory' do
      expect(described_class.ruby_files_from('lib')).to include('lib/fast.rb')
    end

    it 'captures spec files from specs directory' do
      expect(described_class.ruby_files_from('spec')).to include('spec/spec_helper.rb', 'spec/fast_spec.rb')
    end

    context 'with directories .rb' do
      before { Dir.mkdir('create-directory-with-ruby-extension.rb') }

      after { Dir.rmdir('create-directory-with-ruby-extension.rb') }

      it 'ignores the folder' do
        expect(described_class.ruby_files_from('.')).not_to include('create-directory-with-ruby-extension.rb')
      end
    end
  end

  describe 'Fast.expression_from' do
    it { expect(described_class.expression_from(code['1'])).to eq('(int _)') }
    it { expect(described_class.expression_from(code['nil'])).to eq('(nil)') }
    it { expect(described_class.expression_from(code['a = 1'])).to eq('(lvasgn _ (int _))') }
    it { expect(described_class.expression_from(code['[1]'])).to eq('(array (int _))') }
    it { expect(described_class.expression_from(code['def name; person.name end'])).to eq('(def _ (args) (send (send nil? _) _))') }
  end
end
