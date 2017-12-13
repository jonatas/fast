require "spec_helper"
require 'tempfile'

RSpec.describe Fast do

  let(:f) { -> (arg) { Fast::Find.new(arg) } }
  let(:nf) { -> (arg) { Fast::Not.new(arg) } }
  let(:c) { -> (arg) { Fast::Capture.new(arg) } }
  let(:any) { -> (arg) { Fast::Any.new(arg) } }
  let(:all) { -> (arg) { Fast::All.new(arg) } }
  let(:maybe) { -> (arg) { Fast::Maybe.new(arg) } }
  let(:parent) { -> (arg) { Fast::Parent.new(arg) } }
  let(:defined_proc) { described_class::LITERAL }
  let(:code) { -> (string) { Parser::CurrentRuby.parse(string) }  }

  def s(type, *children)
    Parser::AST::Node.new(type, children)
  end

  describe '.expression' do
    it 'from simple string' do
      expect(Fast.expression('...')).to be_a(Fast::Find)
      expect(Fast.expression('$...')).to be_a(Fast::Capture)
      expect(Fast.expression('{}')).to be_a(Fast::Any)
      expect(Fast.expression('[]')).to be_a(Fast::All)

      expect(Fast.expression('?')).to be_a(Fast::Maybe)
      expect(Fast.expression('^')).to be_a(Fast::Parent)
      expect(Fast.expression('\\1')).to be_a(Fast::FindWithCapture)
    end

    it '`!` isolated should be a find' do
      expect(Fast.expression('!')).to be_a(Fast::Find) 
    end

    it '`!` negate expression after it' do
      expect(Fast.expression('! a')).to be_a(Fast::Not)
    end

    it 'allows proc shortcuts' do
      expect(Fast.expression('...')).to eq(f['...'])
      expect(Fast.expression('_')).to eq(f['_'])
    end

    it 'ignore semicolon' do
      expect(Fast.expression(':send')).to eq(Fast.expression('send'))
    end

    it 'ignore empty spaces' do
      expect(Fast.expression('(send     (send     nil                   _)                    _)'))
                    .to eq([f['send'],[f['send'], f['nil'], f['_']],f['_']])
    end

    it 'wraps expressions deeply' do
      expect(Fast.expression('(send (send nil a) b)')).to eq([f['send'], [f['send'], f['nil'], f['a']], f['b']])
      expect(Fast.expression('(send (send (send nil a) b) c)')).to eq([f['send'], [f['send'], [f['send'], f['nil'], f['a']], f['b']], f['c']])
    end

    describe '`{}`' do
      it "works as `or` allowing to match any internal expression" do
        expect( Fast.expression('(send $({int float} _) + $(int _))')).to eq(
          [
            f['send'],
            c[
              [
                any[[f['int'], f['float']]],
                f['_']
              ]
            ], f['+'],
            c[
              [
                f['int'],
                f['_']
              ]
            ]
          ])
      end
    end

    describe '`[]`' do
      it "works as `and` allowing to match all internal expression" do
        puts(Fast.expression('[!str !sym]'))
          puts(all[[nf[f['str']], nf[f['sym']]]])
        expect(Fast.expression('[!str !sym]')).to eq(all[[nf[f['str']], nf[f['sym']]]])
      end
    end

    describe '`!`' do
      it 'negates inverting the logic' do
        expect(Fast.expression('!str')).to eq(nf[f['str']])
      end
      it 'negates nested expressions' do
        expect(Fast.expression('!{str sym}')).to eq(nf[any[[f['str'],f['sym']]]])
      end
      it 'negates entire nodes' do
        expect(Fast.expression('!(int _)')).to eq(nf[[f['int'],f['_']]])
      end
    end

    describe '`?`' do
      it 'allow partial existence' do
        expect(Fast.expression('?str')).to eq(maybe[f['str']])
      end

      it 'allow maybe not combined with `!`' do
        expect(Fast.expression('?!str')).to eq(maybe[nf[f['str']]])
      end

      it 'allow maybe combined with or' do
        expect(Fast.expression('?{str sym}')).to eq(maybe[any[[f['str'], f['sym']]]])
      end
    end

    describe '`$`' do
      it 'captures internal references' do
        expect(Fast.expression('(send (send nil $a) b)')).to eq([f['send'], [f['send'], f['nil'], c[f['a']]], f['b']])
      end

      it 'captures internal nodes' do
        expect(Fast.expression('(send $(send nil a) b)')).to eq([f['send'], c[[f['send'], f['nil'], f['a']]], f['b']])
      end
    end
  end

  describe '.match?' do
    context 'with pure array expression' do
      it 'matches AST code with a pure array' do
        expect(Fast).to be_match(s(:int, 1), [:int, 1])
      end

      it 'matches deeply with sub arrays' do
        expect(Fast).to be_match(s(:send, s(:send, nil, :object), :method), [:send, [:send, nil, :object], :method])
      end

      context 'with complex AST' do
        let(:ast) { code['a += 1'] }
        it 'matches ending expression soon' do
          expect(Fast).to be_match(ast, [:op_asgn, '...'])
        end

        it 'matches going deep in the details' do
          expect(Fast).to be_match(ast, [:op_asgn, '...', '_'])
        end

        it 'matches going deeply with multiple skips' do
          expect(Fast).to be_match(ast, [:op_asgn, '...', '_', '...'])
        end
      end
    end

    context 'with `Fast.expressions`' do
      it { expect(Fast).to be_match(s(:int, 1), '(...)') }
      it { expect(Fast).to be_match(s(:int, 1), '(_ _)') }
    end

    context 'when mixing procs inside expressions' do
      let(:expression) do
        ['_', '_', :+, -> (node) { [:int, :float].include?(node.type)}]
      end

      it 'matches int' do
        expect(Fast).to be_match(code['a += 1'], expression)
      end

      it 'matches float' do
        expect(Fast).to be_match(code['a += 1.2'], expression)
      end

      it 'does not match string' do
        expect(Fast).not_to be_match(code['a += ""'], expression)
      end
    end

    it 'ignores empty spaces' do
      expect(
        Fast.match?(
          s(:send, s(:send, s(:send, nil, :a), :b), :c),
          '(send    (send    (send   nil   _)   _)   _)'
        )
      ).to be_truthy
    end

    describe '`{}`' do
      it 'allows build `or` operator' do
        expect(Fast).to be_match(code['1.2'], '{int float} _')
        expect(Fast).to be_match(code['1'], '{int float} _')
        expect(Fast).not_to be_match(code['""'], '{int float} _')
      end

      it 'works in nested levels' do
        expect(Fast).to be_match(code['1.2 + 1'], '(send ({int float} _) :+ (int _))')
        expect(Fast).to be_match(code['2 + 5'], '(send ({int float} _) + (int _))')
      end

      it 'does not match if the correct operator is missing' do
        expect(Fast).not_to be_match(code['2 - 5'], '(send ({int float} _) + (int _))')
      end

      it 'matches with the correct operator' do
        expect(Fast).to be_match(code['2 - 5'], '(send ({int float} _) {+-} (int _))')
      end
    end

    describe '`[]`' do
      it 'join expressions with `and`' do
        expect(Fast).to be_match(code['3'], '([!str !hash] _)')
      end

      it 'allow join in any level' do
        expect(Fast).to be_match(code['3'], '(int [!1 !2])')
      end
    end

    describe '`not` negates with !' do
      it { expect(Fast).to be_match(code["1.0"], '!(int _)') }
      it { expect(Fast).not_to be_match(code["1"], '!(int _)') }
      it { expect(Fast).to be_match(code[":symbol"], '!({str int float} _)') }
      it { expect(Fast).not_to be_match(code["1"], '!({str int float} _)') }
    end

    describe '`maybe` do partial search with `?`' do
      specify do
        expect(Fast.match?(code["a.b"], '(send (send nil _) _)')).to be_truthy
        expect(Fast.match?(code["a.b"], '(send (send nil a) b)')).to be_truthy
        expect(Fast.match?(code["a.b"], '(send ?(send nil a) b)')).to be_truthy
        expect(Fast.match?(code["b"],   '(send ?(send nil a) b)')).to be_truthy
        expect(Fast.match?(code["b.a"], '(send ?(send nil a) b)')).to be_falsy
      end
    end

    describe 'reuse elements captured previously in the search with `\\<capture-index>`' do
      it 'any level' do
        expect(Fast.match?(s(:send, nil, :a), '(send nil $_)')).to eq([:a])
        expect(Fast.match?(s(:int, 1),        '($(int _))'   )).to eq([s(:int, 1)])
        expect(Fast.match?(s(:sym, :a),       '(sym $_)'     )).to eq([:a])
      end

      it 'allow reuse captured symbols' do
        ast = code["def name; person.name end"]
        expect(Fast.match?(ast,'(def $_ (_) (send (send nil _) \1))')).to eq([:name])
      end

      it 'allow reuse captured nodes' do
        expect(Fast.match?(code["a = 1\nb = 1"], '(begin (lvasgn _ $(...)) (lvasgn _ \1))')).to eq([s(:int, 1)])
      end

      it 'allow reuse captured integers' do
        expect(Fast.match?(code["a = 1\nb = 1"], '(begin (lvasgn _ (int $_)) (lvasgn _ (int \1)))')).to eq([1])
      end
    end

    describe 'capture with `$`' do
      it 'any level' do
        expect(Fast.match?(s(:send, nil, :a), '(send nil $_)')).to eq([:a])
        expect(Fast.match?(s(:int, 1),        '($(int _))'   )).to eq([s(:int, 1)])
        expect(Fast.match?(s(:sym, :a),       '(sym $_)'     )).to eq([:a])
      end

      it 'multiple nodes' do
        expect(
          Fast.match?(
            s(:send, s(:int, 1), :+, s(:int, 2)),
            '(:send $(:int _) :+ $(:int _))'
          )).to eq [s(:int, 1), s(:int, 2)]
      end

      it 'captures specific children' do
        expect(
          Fast.match?(
            s(:send, s(:int, 1), :+, s(:int, 2)),
            '(send (int $_) :+ (int $_))'
          )).to eq [1,2]
      end

      it 'captures complex negated joined condition' do
        expect(Fast.match?(s(:sym, :sym), '$!({str int float} _)')).to eq([s(:sym, :sym)])
      end

      it 'captures diverse things' do
        ast = s(:def,
                :reverse_string,
                s(:args, s(:arg, :string)),
                s(:send, s(:lvar, :string), :reverse))

        expect(Fast.match?(ast, '(def $_ ... ...)')).to eq([:reverse_string])
        expect(Fast.match?(ast, '(def $reverse_string ... ...)')).to eq([:reverse_string])
        expect(Fast.match?(ast, '(def reverse_string (args (arg $_)) ...)')).to eq([:string])
        expect(Fast.match?(ast, '(def reverse_string (args (arg _)) $...)')).to eq([s(:send, s(:lvar, :string), :reverse)])
      end
    end

    describe '`Parent` can follow expression in children with `^`' do
      it "ignores type and search in children using expression following" do
        expect(Fast.match?(code["a = 1"], '^(int _)')).to be_truthy
      end

      it 'captures parent of parent and also ignore non node children' do
        ast = code["b = a = 1"]
        expect(Fast.match?(ast, '$^^(int _)')).to eq([ast])
      end
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

    it 'capture things flatten and unique nodes' do
      result = Fast.search_file('$def', 'sample.rb')
      method_names = result.map(&:children).map(&:first)
      expect(method_names).to eq([:initialize, :welcome])
    end

    specify do
      res = Fast.search_file('$(dstr _)', 'sample.rb')
      strings = res.map{|node|node.loc.expression.source}
      expect(strings).to eq [
        "\"Olá \#{@name}\"",
        "\"Hola \#{@name}\"",
        "\"Hello \#{@name}\""
      ]
    end

    specify do
      res = Fast.search_file('(send nil :puts $...)', 'sample.rb')
      strings = res.select{|n|n.type == :dstr}.map{|node|node.loc.expression.source}
      expect(strings).to eq [
        "\"Olá \#{@name}\"",
        "\"Hola \#{@name}\"",
        "\"Hello \#{@name}\""
      ]
    end

    specify do
      result = Fast.search_file('$(ivar _)', 'sample.rb')
      instance_variable_names = result.map(&:children).map(&:first)
      expect(instance_variable_names).to eq(%i[@lang @name])
    end

    specify do
      result = Fast.search_file('$(lvar _)', 'sample.rb')
      local_variable_names = result.map(&:children).map(&:first)
      expect(local_variable_names).to eq(%i[name language welcome_message message])
    end

    it 'captures const symbol' do
      node, capture = Fast.search_file('(casgn nil $_ ...)', 'sample.rb')
      expect(capture).to eq(:AUTHOR)
      expect(node).to eq(s(:casgn, nil, :AUTHOR, s(:str, "Jônatas Davi Paganini")))
    end

    it 'captures const assignment values' do
      _, capture= Fast.search_file('(casgn nil _ (str $_))', 'sample.rb')
      expect(capture).to eq("Jônatas Davi Paganini")
    end

    describe 'replace' do
      specify do
        expect(
          Fast.replace(
          code['a = 1'],
          '(lvasgn _ ...)',
           -> (node) { replace(node.location.name, 'variable_renamed') }
          )
        ).to eq "variable_renamed = 1"
      end

      specify 'refactor to use delegate instead of create a method' do
        expect(
          Fast.replace(
            code['def name; person.name end'],
            '(def $_ (_) (send (send nil $_) \1))',
          -> (node, captures) { 
              new_source = "delegate :#{captures[0]}, to: :#{captures[1]}"
              replace(node.location.expression, new_source) }
          )
        ).to eq "delegate :name, to: :person"
      end

      specify 'refactor showing how to use any instead of something not empty' do
        expect(
          Fast.replace(
            code['!a.empty?'],
            '(send (send (send nil $_ ) empty?) !)',
          -> (node, captures) { replace(node.location.expression, "#{captures[0]}.any?") }
          )
        ).to eq "a.any?"
      end

      specify 'refactor showing that it replaces deeply in the tree' do
        expect(
          Fast.replace(
            code['puts "something" if !a.empty?'],
            '(send (send (send nil $_ ) empty?) !)',
            -> (node, captures) { replace(node.location.expression, "#{captures[0]}.any?") }
          )
        ).to eq 'puts "something" if a.any?'
      end

      specify 'use `match_index` to filter an specific occurence' do
        expect(
        
          Fast.replace(
            code['create(:a, :b, :c);create(:b, :c, :d)'],
            '(send nil :create)',
            -> (node, captures) {
              if match_index == 2
                replace(node.location.selector, "build_stubbed")
              end
            }
          )
        ).to eq('create(:a, :b, :c);build_stubbed(:b, :c, :d)')
      end

      specify "refactor to use shortcut instead of blocks" do
        expect(Fast.replace(
          code['(1..100).map { |i| i.to_s }'],
           '(block ... (args (arg $_) ) (send (lvar \1) $_))',
            -> (node, captures) {
              replacement = node.children[0].location.expression.source + "(&:#{captures.last})"
              replace(node.location.expression, replacement) }
        )).to eq('(1..100).map(&:to_s)')
      end
    end

    describe "replace file" do
      specify "rename constant" do
        expect(Fast.replace_file(
          'sample.rb',
          '({casgn const} nil AUTHOR )',
          -> (node, _) {
            if node.type == :const
              replace(node.location.expression, "CREATOR")
            else
              replace(node.location.name, "CREATOR")
            end
          }).lines.grep(/CREATOR/).size).to eq 2
      end

      specify "inline local variable" do
        assignment = nil
        expect(Fast.replace_file(
          'sample.rb',
          '({lvar lvasgn } message )',
          -> (node, _) {
            if node.type == :lvasgn
              assignment = node.children.last
              remove(node.location.expression)
            else
              replace(node.location.expression, assignment.location.expression.source)
            end
          }).lines.map(&:chomp).map(&:strip))
            .to include(%|puts [AUTHOR, "wants to say", welcome_message].join(' ')|)
      end
    end

    after do
      File.delete('sample.rb')
    end
  end

  describe '.debug' do
    specify do
      expect do
        Fast.debug do
          Fast.match?(s(:int, 1), [:int, 1])
        end
      end.to output(<<~OUTPUT).to_stdout
         int == (int 1) # => true
         1 == 1 # => true
      OUTPUT
    end
  end

  describe '.capture' do
    it 'captures single element' do
      expect(Fast.capture(code['a = 1'], '(lvasgn _ (int $_))')).to eq(1)
    end

    it 'captures array elements' do
      expect(Fast.capture(code['a = 1'], '(lvasgn $_ (int $_))')).to eq([:a, 1])
    end

    it 'captures nodes' do
      expect(Fast.capture(code['a = 1'], '(lvasgn _ $(int _))')).to eq(code['1'])
    end

    it 'captures multiple nodes' do
      expect(Fast.capture(code['a = 1'], '$(lvasgn _ (int _))')).to eq(code['a = 1'])
    end
  end

  describe '.ruby_files_from' do
    it 'captures ruby files from directory' do
      expect(Fast.ruby_files_from('lib')).to match_array(['lib/fast.rb'])
      expect(Fast.ruby_files_from('spec')).to match_array(['spec/spec_helper.rb', 'spec/fast_spec.rb'])
    end
  end

  describe '.experiment' do
    let(:spec) do
      tempfile = Tempfile.new("some_spec.rb")
      tempfile.write <<~RUBY
        let(:user) { create(:user) }
        let(:address) { create(:address) }
      RUBY
      tempfile.close
      tempfile.path
    end

    subject { Fast::Experiment.new(spec, '(send nil :create)' ) }

    describe "#filename" do
      it { expect(subject.experimental_filename(1)).to include('experiment_1') }
    end

    describe "#replace" do
      let(:replacement) { -> (node, _) { replace(node.loc.selector, 'build_stubbed') } }
      specify do
        expect(subject.partial_replace(replacement, 1)).to eq(<<~RUBY.chomp)
          let(:user) { build_stubbed(:user) }
          let(:address) { create(:address) }
        RUBY
        expect(subject.partial_replace(replacement, 2)).to eq(<<~RUBY.chomp)
          let(:user) { create(:user) }
          let(:address) { build_stubbed(:address) }
        RUBY
      end
    end

    describe "#suggest_combinations" do
      before do
        subject.ok(1)
        subject.fail(2)
        subject.ok(3)
        subject.ok(4)
        subject.ok(5)
      end

      specify do
        expect(subject.ok_experiments).to eq([1, 3, 4, 5])
        expect(subject.suggest_combinations).to match_array([
          [1, 3], [1, 4], [1, 5], [3, 4], [3, 5], [4, 5]
        ])

        subject.ok([1,3])
        subject.fail([1,4])

        expect(subject.suggest_combinations).to eq([[4, 5], [1, 3, 4], [1, 3, 5]])

        subject.fail([1,3,4])

        expect(subject.suggest_combinations).to eq([[4, 5], [ 1, 3, 5]])

        subject.fail([4,5])

        expect(subject.suggest_combinations).to eq([[ 1, 3, 5]])

        subject.ok([1,3,5])

        expect(subject.suggest_combinations).to eq([[1, 3, 4, 5]])

        subject.ok([1, 3, 4, 5])

        expect(subject.suggest_combinations).to be_empty
      end
    end
  end
end
