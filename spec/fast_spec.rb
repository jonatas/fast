# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

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
    Astrolabe::Node.new(type, children)
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
        expect(described_class).to be_match(s(:int, 1), '#custom_method')
        expect(described_class).not_to be_match(s(:int, 2), '#custom_method')
      end
    end
  end

  describe '.match?' do
    context 'with pure array expression' do
      it 'matches AST code with a pure array' do
        expect(described_class).to be_match(s(:int, 1), [:int, 1])
      end

      it 'matches deeply with sub arrays' do
        expect(described_class).to be_match(s(:send, s(:send, nil, :object), :method), [:send, [:send, nil, :object], :method])
      end
    end

    context 'with complex AST' do
      let(:ast) { code['a += 1'] }

      it 'matches ending expression soon' do
        expect(described_class).to be_match(ast, [:op_asgn, '...'])
      end

      it 'matches going deep in the details' do
        expect(described_class).to be_match(ast, [:op_asgn, '...', '_'])
      end

      it 'matches going deeply with multiple skips' do
        expect(described_class).to be_match(ast, [:op_asgn, '...', '_', '...'])
      end
    end

    context 'with `Fast.expressions`' do
      it { expect(described_class).to be_match(s(:int, 1), '(...)') }
      it { expect(described_class).to be_match(s(:int, 1), '(_ _)') }
      it { expect(described_class).to be_match(s(:int, 1), '(int .odd?)') }
      it { expect(described_class).to be_match(nil, '.nil?') }
      it { expect(described_class).not_to be_match(s(:int, 1), '(int .even?)') }
      it { expect(described_class).to be_match(code['"string"'], '(str "string")') }

      context 'with astrolable node methods' do
        it { expect(described_class).to be_match(code['method'], '.send_type?') }
        it { expect(described_class).to be_match(code['a.b'], '(.root? (!.root?))') }
        it { expect(described_class).not_to be_match(code['a.b'], '(!.root? (.root?))') }
      end
    end

    context 'when mixing procs inside expressions' do
      let(:expression) do
        ['_', '_', :+, ->(node) { %i[int float].include?(node.type) }]
      end

      it 'matches int' do
        expect(described_class).to be_match(code['a += 1'], expression)
      end

      it 'matches float' do
        expect(described_class).to be_match(code['a += 1.2'], expression)
      end

      it 'does not match string' do
        expect(described_class).not_to be_match(code['a += ""'], expression)
      end
    end

    it 'ignores empty spaces' do
      expect(described_class).to be_match(
        s(:send, s(:send, s(:send, nil, :a), :b), :c),
        '(send    (send    (send   nil   _)   _)   _)'
      )
    end

    describe '`{}`' do
      it 'allows match `or` operator' do
        expect(described_class).to be_match(code['1.2'], '{int float} _')
      end

      it 'allows match first case' do
        expect(described_class).to be_match(code['1'], '{int float} _')
      end

      it 'return false if does not match' do
        expect(described_class).not_to be_match(code['""'], '{int float} _')
      end

      it 'works in nested levels' do
        expect(described_class).to be_match(code['1.2 + 1'], '(send ({int float} _) :+ (int _))')
      end

      it 'works with complex operations nested levels' do
        expect(described_class).to be_match(code['2 + 5'], '(send ({int float} _) + (int _))')
      end

      it 'does not match if the correct operator is missing' do
        expect(described_class).not_to be_match(code['2 - 5'], '(send ({int float} _) + (int _))')
      end

      it 'matches with the correct operator' do
        expect(described_class).to be_match(code['2 - 5'], '(send ({int float} _) {+-} (int _))')
      end

      it 'matches multiple symbols' do
        expect(described_class).to be_match(code['b'], '(send {nil ...} b)')
      end

      it 'allows the maybe concept' do
        expect(described_class).to be_match(code['a.b'], '(send {nil ...} b)')
      end
    end

    describe '`[]`' do
      it 'join expressions with `and`' do
        expect(described_class).to be_match(code['3'], '([!str !hash] _)')
      end

      it 'allow join in any level' do
        expect(described_class).to be_match(code['3'], '(int [!1 !2])')
      end
    end

    describe '`not` negates with !' do
      it { expect(described_class).to be_match(code['1.0'], '!(int _)') }
      it { expect(described_class).not_to be_match(code['1'], '!(int _)') }
      it { expect(described_class).to be_match(code[':symbol'], '!({str int float} _)') }
      it { expect(described_class).not_to be_match(code['1'], '!({str int float} _)') }
    end

    describe '`maybe` do partial search with `?`' do
      it 'allow maybe is a method call`' do
        expect(described_class).to be_match(code['a.b'], '(send ?(send nil a) b)')
      end

      it 'allow without the method call' do
        expect(described_class).to be_match(code['b'],   '(send ?(send nil a) b)')
      end

      it 'does not match if the node does not satisfy the expressin' do
        expect(described_class).not_to be_match(code['b.a'], '(send ?(send nil a) b)')
      end
    end

    describe '`$` for capturing' do
      it 'last children' do
        expect(described_class.match?(s(:send, nil, :a), '(send nil $_)')).to eq([:a])
      end

      it 'the entire node' do
        expect(described_class.match?(s(:int, 1),        '($(int _))')).to eq([s(:int, 1)])
      end

      it 'the value' do
        expect(described_class.match?(s(:sym, :a),       '(sym $_)')).to eq([:a])
      end

      it 'multiple nodes' do
        expect(described_class.match?(s(:send, s(:int, 1), :+, s(:int, 2)), '(:send $(:int _) :+ $(:int _))')).to eq([s(:int, 1), s(:int, 2)])
      end

      it 'specific children' do
        expect(described_class.match?(s(:send, s(:int, 1), :+, s(:int, 2)), '(send (int $_) :+ (int $_))')).to eq([1, 2])
      end

      it 'complex negated joined condition' do
        expect(described_class.match?(s(:sym, :sym), '$!({str int float} _)')).to eq([s(:sym, :sym)])
      end

      describe 'capture method' do
        let(:ast) { code['def reverse_string(string) string.reverse end'] }

        it 'anonymously name' do
          expect(described_class.match?(ast, '(def $_ ... ...)')).to eq([:reverse_string])
        end

        it 'static name' do
          expect(described_class.match?(ast, '(def $reverse_string ... ...)')).to eq([:reverse_string])
        end

        it 'parameter' do
          expect(described_class.match?(ast, '(def reverse_string (args (arg $_)) ...)')).to eq([:string])
        end

        it 'content' do
          expect(described_class.match?(ast, '(def reverse_string (args (arg _)) $...)')).to eq([s(:send, s(:lvar, :string), :reverse)])
        end
      end

      describe 'capture symbol in multiple conditions' do
        let(:expression) { '(send {nil ...} $_)' }

        it { expect(described_class.match?(code['b'], expression)).to eq([:b]) }
        it { expect(described_class.match?(code['a.b'], expression)).to eq([:b]) }
      end
    end

    describe '\\<capture-index> to match with previous captured symbols' do
      it 'allow capture method name and reuse in children calls' do
        ast = code['def name; person.name end']
        expect(described_class.match?(ast, '(def $_ (_) (send (send nil _) \1))')).to eq([:name])
      end

      it 'captures local variable values in multiple nodes' do
        expect(described_class.match?(code["a = 1\nb = 1"], '(begin (lvasgn _ $(...)) (lvasgn _ \1))')).to eq([s(:int, 1)])
      end

      it 'allow reuse captured integers' do
        expect(described_class.match?(code["a = 1\nb = 1"], '(begin (lvasgn _ (int $_)) (lvasgn _ (int \1)))')).to eq([1])
      end
    end

    describe '`Parent` can follow expression in children with `^`' do
      it 'ignores type and search in children using expression following' do
        expect(described_class).to be_match(code['a = 1'], '^(int _)')
      end

      it 'captures parent of parent and also ignore non node children' do
        ast = code['b = a = 1']
        expect(described_class.match?(ast, '$^^(int _)')).to eq([ast])
      end
    end

    describe '%<argument-index> to bind an external argument into the expression' do
      it 'binds extra arguments into the expression' do
        expect(described_class).to be_match(code['a = 1'], '(lvasgn %1 (int _))', :a)
        expect(described_class).to be_match(code['"test"'], '(str %1)', 'test')
        expect(described_class).to be_match(code['"test"'], '(%1 %2)', :str, 'test')
        expect(described_class).to be_match(code[':symbol'], '(%1 %2)', :sym, :symbol)
        expect(described_class).to be_match(code[':symbol'], '{%1 %2}', :sym, :str)
        expect(described_class).not_to be_match(code['a = 1'], '(lvasgn %1 (int _))', :b)
        expect(described_class).not_to be_match(code['1'], '{%1 %2}', :sym, :str)
      end
    end
  end

  describe '.replace' do
    subject { described_class.replace(example, expression, &replacement) }

    context 'with a local variable rename' do
      let(:example) { code['a = 1'] }
      let(:expression) { '(lvasgn _ ...)' }
      let(:replacement) { ->(node) { replace(node.location.name, 'variable_renamed') } }

      it { is_expected.to eq 'variable_renamed = 1' }
    end

    context 'with the method with a `delegate` call' do
      let(:example) { code['def name; person.name end'] }
      let(:expression) { '(def $_ (_) (send (send nil $_) \1))' }
      let(:replacement) do
        lambda do |node, captures|
          new_source = "delegate :#{captures[0]}, to: :#{captures[1]}"
          replace(node.location.expression, new_source)
        end
      end

      it { is_expected.to eq('delegate :name, to: :person') }
    end

    context 'when call !a.empty?` with `a.any?`' do
      let(:example) { code['!a.empty?'] }
      let(:expression) { '(send (send (send nil $_ ) :empty?) !)' }
      let(:replacement) { ->(node, captures) { replace(node.location.expression, "#{captures[0]}.any?") } }

      it { is_expected.to eq('a.any?') }
    end

    context 'when use `match_index` to filter an specific occurence' do
      let(:example) { code['create(:a, :b, :c);create(:b, :c, :d)'] }
      let(:expression) { '(send nil :create)' }
      let(:replacement) { ->(node, _captures) { replace(node.location.selector, 'build_stubbed') if match_index == 2 } }

      it { is_expected.to eq('create(:a, :b, :c);build_stubbed(:b, :c, :d)') }
    end

    context 'when use &:method shortcut instead of blocks' do
      let(:example) { code['(1..100).map { |i| i.to_s }'] }
      let(:expression) { '(block ... (args (arg $_) ) (send (lvar \1) $_))' }
      let(:replacement) do
        lambda do |node, captures|
          replacement = node.children[0].location.expression.source + "(&:#{captures.last})"
          replace(node.location.expression, replacement)
        end
      end

      it { is_expected.to eq('(1..100).map(&:to_s)') }
    end
  end

  describe 'search in files' do
    before do
      File.open('sample.rb', 'w+') do |file|
        file.puts <<~RUBY
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

    describe 'replace file' do
      context 'with rename constant example' do
        let(:rename_const) do
          described_class.replace_file('sample.rb', '({casgn const} nil AUTHOR )') do |node|
            if node.type == :const
              replace(node.location.expression, 'CREATOR')
            else
              replace(node.location.name, 'CREATOR')
            end
          end
        end

        it 'replaces all occurrences' do # rubocop:disable RSpec/ExampleLength
          expect(rename_const).to eq(<<~RUBY.chomp)
            class SelfPromotion
              CREATOR = "Jônatas Davi Paganini"
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
                message = [CREATOR, "wants to say", welcome_message]
                puts message.join(' ')
              end
            end
          RUBY
        end
      end

      context 'when inline local variable example' do
        let(:inline_var) do
          described_class.replace_file('sample.rb', '({lvar lvasgn } message )') do |node, _|
            if node.type == :lvasgn
              @assignment = node.children.last
              remove(node.location.expression)
            else
              replace(node.location.expression,
                      @assignment.location.expression.source) # rubocop:disable RSpec/InstanceVariable
            end
          end
        end

        it 'replaces all occurrences' do
          expect(inline_var).to eq(<<~RUBY.chomp)
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
                welcome_message = new('friend', 'en')\n\s\s\s\s
                puts [AUTHOR, "wants to say", welcome_message].join(' ')
              end
            end
          RUBY
        end
      end
    end
  end

  describe '.debug' do
    specify do
      expect do
        described_class.debug do
          described_class.match?(s(:int, 1), [:int, 1])
        end
      end.to output(<<~OUTPUT).to_stdout
        int == (int 1) # => true
        1 == 1 # => true
      OUTPUT
    end
  end

  describe '.capture' do
    it 'single element' do
      expect(described_class.capture(code['a = 1'], '(lvasgn _ (int $_))')).to eq(1)
    end

    it 'array elements' do
      expect(described_class.capture(code['a = 1'], '(lvasgn $_ (int $_))')).to eq([:a, 1])
    end

    it 'nodes' do
      expect(described_class.capture(code['a = 1'], '(lvasgn _ $(int _))')).to eq(code['1'])
    end

    it 'multiple nodes' do
      expect(described_class.capture(code['a = 1'], '$(lvasgn _ (int _))')).to eq(code['a = 1'])
    end
  end

  describe '.ruby_files_from' do
    it 'captures ruby files from directory' do
      expect(described_class.ruby_files_from('lib')).to include('lib/fast.rb')
    end

    it 'captures spec files from specs directory' do
      expect(described_class.ruby_files_from('spec')).to include('spec/spec_helper.rb', 'spec/fast_spec.rb')
    end
  end

  describe 'Fast.expression_from' do
    it { expect(described_class.expression_from(code['1'])).to eq('(int _)') }
    it { expect(described_class.expression_from(code['nil'])).to eq('(nil)') }
    it { expect(described_class.expression_from(code['a = 1'])).to eq('(lvasgn _ (int _))') }
    it { expect(described_class.expression_from(code['def name; person.name end'])).to eq('(def _ (args) (send (send nil _) _))') }
  end
end
