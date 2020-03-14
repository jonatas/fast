# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Fast do
  let(:f) { ->(arg) { Fast::Find.new(arg) } }
  let(:nf) { ->(arg) { Fast::Not.new(arg) } }
  let(:c) { ->(arg) { Fast::Capture.new(arg) } }
  let(:any) { ->(arg) { Fast::Any.new(arg) } }
  let(:all) { ->(arg) { Fast::All.new(arg) } }
  let(:maybe) { ->(arg) { Fast::Maybe.new(arg) } }
  let(:parent) { ->(arg) { Fast::Parent.new(arg) } }
  let(:defined_proc) { described_class::LITERAL }
  let(:code) { ->(string) { described_class.ast(string) } }

  def s(type, *children)
    Fast::Node.new(type, children)
  end

  describe '.expression' do
    it 'parses ... as Find' do
      expect(described_class.expression('...')).to be_a(Fast::Find)
    end

    it 'parses $ as Capture' do
      expect(described_class.expression('$...')).to be_a(Fast::Capture)
    end

    it 'parses #custom_method as method call' do
      expect(described_class.expression('#method')).to be_a(Fast::MethodCall)
    end

    it 'parses `.method?` into instance method calls' do
      expect(described_class.expression('.odd?')).to be_a(Fast::InstanceMethodCall)
    end

    it 'parses quoted values as strings' do
      expect(described_class.expression('"string"')).to be_a(Fast::FindString)
    end

    it 'parses {} as Any' do
      expect(described_class.expression('{}')).to be_a(Fast::Any)
    end

    it 'parses [] as All' do
      expect(described_class.expression('[]')).to be_a(Fast::All)
    end

    it 'parses ? as Maybe' do
      expect(described_class.expression('?')).to be_a(Fast::Maybe)
    end

    it 'parses ^ as Parent' do
      expect(described_class.expression('^')).to be_a(Fast::Parent)
    end

    it 'parses \\1 as FindWithCapture' do
      expect(described_class.expression('\\1')).to be_a(Fast::FindWithCapture)
    end

    it 'binds %1 as first argument' do
      expect(described_class.expression('%1')).to be_a(Fast::FindFromArgument)
    end

    it '`!` isolated should be a find' do
      expect(described_class.expression('!')).to be_a(Fast::Find)
    end

    it '`!` negate expression after it' do
      expect(described_class.expression('! a')).to be_a(Fast::Not)
    end

    it 'allows ... as a proc shortcuts' do
      expect(described_class.expression('...')).to eq(f['...'])
    end

    it 'allows _ as a proc shortcuts' do
      expect(described_class.expression('_')).to eq(f['_'])
    end

    it 'allows setter methods in find' do
      expect(described_class.expression('attribute=')).to eq(f['attribute='])
    end

    it 'ignores semicolon' do
      expect(described_class.expression(':send')).to eq(described_class.expression('send'))
    end

    it 'ignores empty spaces' do
      expect(described_class.expression('(send     (send     nil                   _)                    _)'))
        .to eq([f['send'], [f['send'], f['nil'], f['_']], f['_']])
    end

    it 'wraps expressions deeply' do
      expect(described_class.expression('(send (send nil a) b)')).to eq([f['send'], [f['send'], f['nil'], f['a']], f['b']])
    end

    it 'wraps expressions in multiple levels' do
      expect(described_class.expression('(send (send (send nil a) b) c)')).to eq([f['send'], [f['send'], [f['send'], f['nil'], f['a']], f['b']], f['c']])
    end

    describe '`{}`' do
      it 'works as `or` allowing to match any internal expression' do
        expect(described_class.expression('(send $({int float} _) + $(int _))')).to eq([f['send'], c[[any[[f['int'], f['float']]], f['_']]], f['+'], c[[f['int'], f['_']]]])
      end
    end

    describe '`[]`' do
      it 'works as `and` allowing to match all internal expression' do
        puts(described_class.expression('[!str !sym]'))
        puts(all[[nf[f['str']], nf[f['sym']]]])
        expect(described_class.expression('[!str !sym]')).to eq(all[[nf[f['str']], nf[f['sym']]]])
      end
    end

    describe '`!`' do
      it 'negates inverting the logic' do
        expect(described_class.expression('!str')).to eq(nf[f['str']])
      end

      it 'negates nested expressions' do
        expect(described_class.expression('!{str sym}')).to eq(nf[any[[f['str'], f['sym']]]])
      end

      it 'negates entire nodes' do
        expect(described_class.expression('!(int _)')).to eq(nf[[f['int'], f['_']]])
      end
    end

    describe '`?`' do
      it 'allow partial existence' do
        expect(described_class.expression('?str')).to eq(maybe[f['str']])
      end

      it 'allow maybe not combined with `!`' do
        expect(described_class.expression('?!str')).to eq(maybe[nf[f['str']]])
      end

      it 'allow maybe combined with or' do
        expect(described_class.expression('?{str sym}')).to eq(maybe[any[[f['str'], f['sym']]]])
      end
    end

    describe '`$`' do
      it 'captures internal references' do
        expect(described_class.expression('(send (send nil $a) b)')).to eq([f['send'], [f['send'], f['nil'], c[f['a']]], f['b']])
      end

      it 'captures internal nodes' do
        expect(described_class.expression('(send $(send nil a) b)')).to eq([f['send'], c[[f['send'], f['nil'], f['a']]], f['b']])
      end
    end

    describe '#custom_method' do
      before do
        Kernel.class_eval do
          def custom_method(node)
            (node.type == :int) && (node.children == [1])
          end
        end
      end

      after do
        Kernel.class_eval do
          undef :custom_method
        end
      end

      it 'allow interpolate custom methods' do
        expect(described_class).to be_match('#custom_method', s(:int, 1))
        expect(described_class).not_to be_match('#custom_method', s(:int, 2))
      end
    end
  end

  describe '.match?' do
    context 'with pure array expression' do
      it 'matches AST code with a pure array' do
        expect(described_class).to be_match([:int, 1], s(:int, 1))
      end

      it 'matches deeply with sub arrays' do
        expect(described_class).to be_match([:send, [:send, nil, :object], :method], s(:send, s(:send, nil, :object), :method))
      end
    end

    context 'with complex AST' do
      let(:ast) { code['a += 1'] }

      it 'matches ending expression soon' do
        expect(described_class).to be_match([:op_asgn, '...'], ast)
      end

      it 'matches going deep in the details' do
        expect(described_class).to be_match([:op_asgn, '...', '_'], ast)
      end

      it 'matches going deeply with multiple skips' do
        expect(described_class).to be_match([:op_asgn, '...', '_', '...'], ast)
      end
    end

    context 'with `Fast.expressions`' do
      it { expect(described_class).to be_match('(...)', s(:int, 1)) }
      it { expect(described_class).to be_match('(_ _)', s(:int, 1)) }
      it { expect(described_class).to be_match('(int .odd?)', s(:int, 1)) }
      it { expect(described_class).to be_match('.nil?', nil) }
      it { expect(described_class).not_to be_match('(int .even?)', s(:int, 1)) }
      it { expect(described_class).to be_match('(str "string")', code['"string"']) }
      it { expect(described_class).to be_match('(float 111.2345)', code['111.2345']) }
      it { expect(described_class).to be_match('(const nil I18n)', code['I18n']) }

      context 'with astrolable node methods' do
        it { expect(described_class).to be_match('.send_type?', code['method']) }
        it { expect(described_class).to be_match('(.root? (!.root?))', code['a.b']) }
        it { expect(described_class).not_to be_match('(!.root? (.root?))', code['a.b']) }
      end
    end

    context 'when mixing procs inside expressions' do
      let(:expression) do
        ['_', '_', :+, ->(node) { %i[int float].include?(node.type) }]
      end

      it 'matches int' do
        expect(described_class).to be_match(expression, code['a += 1'])
      end

      it 'matches float' do
        expect(described_class).to be_match(expression, code['a += 1.2'])
      end

      it 'does not match string' do
        expect(described_class).not_to be_match(expression, code['a += ""'])
      end
    end

    it 'ignores empty spaces' do
      expect(described_class).to be_match(
        '(send    (send    (send   nil   _)   _)   _)',
        s(:send, s(:send, s(:send, nil, :a), :b), :c)
      )
    end

    describe '`{}`' do
      it 'allows match `or` operator' do
        expect(described_class).to be_match('{int float} _', code['1.2'])
      end

      it 'allows match first case' do
        expect(described_class).to be_match('{int float} _', code['1'])
      end

      it 'return false if does not match' do
        expect(described_class).not_to be_match('{int float} _', code['""'])
      end

      it 'works in nested levels' do
        expect(described_class).to be_match('(send ({int float} _) :+ (int _))', code['1.2 + 1'])
      end

      it 'works with complex operations nested levels' do
        expect(described_class).to be_match('(send ({int float} _) + (int _))', code['2 + 5'])
      end

      it 'does not match if the correct operator is missing' do
        expect(described_class).not_to be_match('(send ({int float} _) + (int _))', code['2 - 5'])
      end

      it 'matches with the correct operator' do
        expect(described_class).to be_match('(send ({int float} _) {+-} (int _))', code['2 - 5'])
      end

      it 'matches multiple symbols' do
        expect(described_class).to be_match('(send {nil ...} b)', code['b'])
      end

      it 'allows the maybe concept' do
        expect(described_class).to be_match('(send {nil ...} b)', code['a.b'])
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

    describe '`maybe` do partial search with `?`' do
      it 'allow maybe is a method call`' do
        expect(described_class).to be_match('(send ?(send nil a) b)', code['a.b'])
      end

      it 'allow without the method call' do
        expect(described_class).to be_match('(send ?(send nil a) b)', code['b'])
      end

      it 'does not match if the node does not satisfy the expressin' do
        expect(described_class).not_to be_match('(send ?(send nil a) b)', code['b.a'])
      end
    end

    describe '`$` for capturing' do
      it 'last children' do
        expect(described_class.match?('(send nil $_)', s(:send, nil, :a))).to eq([:a])
      end

      it 'the entire node' do
        expect(described_class.match?('($(int _))', s(:int, 1))).to eq([s(:int, 1)])
      end

      it 'the value' do
        expect(described_class.match?('(sym $_)', s(:sym, :a))).to eq([:a])
      end

      it 'multiple nodes' do
        expect(described_class.match?('(:send $(:int _) :+ $(:int _))', s(:send, s(:int, 1), :+, s(:int, 2)))).to eq([s(:int, 1), s(:int, 2)])
      end

      it 'specific children' do
        expect(described_class.match?('(send (int $_) :+ (int $_))', s(:send, s(:int, 1), :+, s(:int, 2)))).to eq([1, 2])
      end

      it 'complex negated joined condition' do
        expect(described_class.match?('$!({str int float} _)', s(:sym, :sym))).to eq([s(:sym, :sym)])
      end

      describe 'capture method' do
        let(:ast) { code['def reverse_string(string) string.reverse end'] }

        it 'anonymously name' do
          expect(described_class.match?('(def $_ ... ...)', ast)).to eq([:reverse_string])
        end

        it 'static name' do
          expect(described_class.match?('(def $reverse_string ... ...)', ast)).to eq([:reverse_string])
        end

        it 'parameter' do
          expect(described_class.match?('(def reverse_string (args (arg $_)) ...)', ast)).to eq([:string])
        end

        it 'content' do
          expect(described_class.match?('(def reverse_string (args (arg _)) $...)', ast)).to eq([s(:send, s(:lvar, :string), :reverse)])
        end
      end

      describe 'capture symbol in multiple conditions' do
        let(:expression) { '(send {nil ...} $_)' }

        it { expect(described_class.match?(expression, code['b'])).to eq([:b]) }
        it { expect(described_class.match?(expression, code['a.b'])).to eq([:b]) }
      end
    end

    describe '\\<capture-index> to match with previous captured symbols' do
      it 'allow capture method name and reuse in children calls' do
        ast = code['def name; person.name end']
        expect(described_class.match?('(def $_ (_) (send (send nil _) \1))', ast)).to eq([:name])
      end

      it 'captures local variable values in multiple nodes' do
        expect(described_class.match?('(begin (lvasgn _ $(...)) (lvasgn _ \1))', code["a = 1\nb = 1"])).to eq([s(:int, 1)])
      end

      it 'allow reuse captured integers' do
        expect(described_class.match?('(begin (lvasgn _ (int $_)) (lvasgn _ (int \1)))', code["a = 1\nb = 1"])).to eq([1])
      end
    end

    describe '`Parent` can follow expression in children with `^`' do
      it 'ignores type and search in children using expression following' do
        expect(described_class).to be_match('^(int _)', code['a = 1'])
      end

      it 'captures parent of parent and also ignore non node children' do
        ast = code['b = a = 1']
        expect(described_class.match?('$^^(int _)', ast)).to eq([ast])
      end
    end

    describe '%<argument-index> to bind an external argument into the expression' do
      it 'binds extra arguments into the expression' do
        expect(described_class).to be_match('(lvasgn %1 (int _))', code['a = 1'], :a)
        expect(described_class).to be_match('(str %1)', code['"test"'], 'test')
        expect(described_class).to be_match('(%1 %2)', code['"test"'], :str, 'test')
        expect(described_class).to be_match('(%1 %2)', code[':symbol'], :sym, :symbol)
        expect(described_class).to be_match('{%1 %2}', code[':symbol'], :str, :sym)
        expect(described_class).not_to be_match('(lvasgn %1 (int _))', code['a = 1'], :b)
        expect(described_class).not_to be_match('{%1 %2}', code['1'], :str, :sym)
      end
    end
  end

  describe '#search' do
    subject(:search) { described_class.search(pattern, node, *args) }

    context 'with extra args' do
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
      method_names = described_class.search_file('(def $_)', 'sample.rb').grep(Symbol)
      expect(method_names).to eq(%i[initialize welcome])
    end

    it 'captures const symbol' do
      _, capture = described_class.search_file('(casgn nil $_ ...)', 'sample.rb')
      expect(capture).to eq(:AUTHOR)
    end

    it 'captures const assignment values' do
      _, capture = described_class.search_file('(casgn nil _ (str $_))', 'sample.rb')
      expect(capture).to eq('Jônatas Davi Paganini')
    end

    describe '.capture_file' do
      it 'captures puts arguments' do
        res = described_class.capture_file('(send nil puts $(dstr ))', 'sample.rb')
        strings = res.map { |node| node.loc.expression.source }
        expect(strings).to eq(['"Olá #{@name}"', '"Hola #{@name}"', '"Hello #{@name}"'])
      end

      it 'capture dynamic strings into nodes' do
        res = described_class.capture_file('$(dstr _)', 'sample.rb')
        strings = res.map { |node| node.loc.expression.source }
        expect(strings).to eq(['"Olá #{@name}"', '"Hola #{@name}"', '"Hello #{@name}"'])
      end

      it 'captures instance variables' do
        ivars = described_class.capture_file('(ivasgn $_)', 'sample.rb')
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
      results = described_class.search_all('(casgn nil VERSION)', ['lib/fast/version.rb'])
      expect(results).to have_key('lib/fast/version.rb')
      expect(results['lib/fast/version.rb'].map { |n| n.loc.expression.source }).to eq(["VERSION = '#{Fast::VERSION}'"])
    end

    context 'with empty file' do
      before { File.open('test-empty-file.rb', 'w+') { |f| f.puts '' } }

      after { File.delete('test-empty-file.rb') }

      it { expect(described_class.search_all('(casgn nil VERSION)', ['test-empty-file.rb'])).to be_nil }
    end
  end

  describe '.capture_all' do
    it 'allow search multiple files in the same time' do
      results = described_class.capture_all('(casgn nil VERSION (str $_))', ['lib/fast/version.rb'])
      expect(results).to eq('lib/fast/version.rb' => [Fast::VERSION])
    end

    context 'with empty file' do
      before { File.open('test-empty-file.rb', 'w+') { |f| f.puts '' } }

      after { File.delete('test-empty-file.rb') }

      it { expect(described_class.capture_all('(casgn nil VERSION)', ['test-empty-file.rb'])).to be_nil }
    end
  end

  describe '.debug' do
    specify do
      expect do
        described_class.debug do
          described_class.match?([:int, 1], s(:int, 1))
        end
      end.to output(<<~OUTPUT).to_stdout
        int == (int 1) # => true
        1 == 1 # => true
      OUTPUT
    end
  end

  describe '.capture' do
    it 'single element' do
      expect(described_class.capture('(lvasgn _ (int $_))', code['a = 1'])).to eq([1])
    end

    it 'array elements' do
      expect(described_class.capture('(lvasgn $_ (int $_))', code['a = 1'])).to eq([:a, 1])
    end

    it 'nodes' do
      expect(described_class.capture('(lvasgn _ $(int _))', code['a = 1'])).to eq([code['1']])
    end

    it 'multiple nodes' do
      expect(described_class.capture('$(lvasgn _ (int _))', code['a = 1'])).to eq([code['a = 1']])
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
    it { expect(described_class.expression_from(code['def name; person.name end'])).to eq('(def _ (args) (send (send nil _) _))') }
  end

  describe 'Find and descendant classes' do
    describe '#to_s' do
      it { expect(described_class.expression('...').to_s).to eq('f[...]') }
      it { expect(described_class.expression('$...').to_s).to eq('c[f[...]]') }
      it { expect(described_class.expression('{ a b }').to_s).to eq('any[f[a], f[b]]') }
      it { expect(described_class.expression('\\1').to_s).to eq('fc[\\1]') }
      it { expect(described_class.expression('^int').to_s).to eq('^f[int]') }
      it { expect(described_class.expression('%1').to_s).to eq('find_with_arg[\\0]') }
    end
  end
end
