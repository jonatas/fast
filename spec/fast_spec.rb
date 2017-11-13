require "spec_helper"

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

  context '.expression' do
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

    context 'Any sequence' do
      specify do
        expect(
          Fast.expression(
            '(send $({int float} _) + $(int _))'
          )
        ).to eq(
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
    context 'All sequence' do
      specify do
        puts(Fast.expression('[!str !sym]'))
          puts(all[[nf[f['str']], nf[f['sym']]]])
        expect(Fast.expression('[!str !sym]')).to eq(all[[nf[f['str']], nf[f['sym']]]])
      end
    end

    context 'Not negates with !' do
      specify do
        expect(Fast.expression('!str')).to eq(nf[f['str']])
        expect(Fast.expression('!{str sym}')).to eq(nf[any[[f['str'],f['sym']]]])
        expect(Fast.expression('!(int _)')).to eq(nf[[f['int'],f['_']]])
        expect(Fast.expression('{_ !_}')).to eq(any[[f['_'],nf[f['_']]]])
      end
    end

    context 'Maybe allow partial existence with ?' do
      specify do
        expect(Fast.expression('?str')).to eq(maybe[f['str']])
        expect(Fast.expression('?!str')).to eq(maybe[nf[f['str']]])
        expect(Fast.expression('?{str sym}')).to eq(maybe[any[[f['str'], f['sym']]]])
      end
    end

    context 'capture with $' do
      it 'expressions deeply' do
        expect(Fast.expression('(send (send nil a) b)')).to eq([f['send'], [f['send'], f['nil'], f['a']], f['b']])
        expect(Fast.expression('(send (send (send nil a) b) c)')).to eq([f['send'], [f['send'], [f['send'], f['nil'], f['a']], f['b']], f['c']])
      end

      it 'multiple levels' do
        expect(Fast.expression('(send (send nil $a) b)')).to eq([f['send'], [f['send'], f['nil'], c[f['a']]], f['b']])
        expect(Fast.expression('(send $(send nil a) b)')).to eq([f['send'], c[[f['send'], f['nil'], f['a']]], f['b']])
      end
    end
  end

  describe '.match?' do
    it 'matches AST code with a pure array' do
      expect(Fast.match?(s(:int, 1), [:int, 1])).to be_truthy
      expect(Fast.match?(s(:send, nil, :method), [:send, nil, :method])).to be_truthy
      expect(Fast.match?(s(:send, s(:send, nil, :object), :method), [:send, [:send, nil, :object], :method])).to be_truthy
    end

    it 'works with `Fast.expressions`' do
      expect(Fast.match?(s(:int, 1), '(...)')).to be_truthy
      expect(Fast.match?(s(:int, 1), '(_ _)')).to be_truthy
    end

    it 'matches ast code literal' do
      expect(Fast.match?(s(:int, 1), [:int, 1])).to be_truthy
    end

    it 'matches ast deeply ' do
      ast = s(:op_asgn, s(:lvasgn, :a), :+, s(:int, 1))
      expect(
        Fast.match?(ast, [:op_asgn, '...']) &&
        Fast.match?(ast, [:op_asgn, '...', '_', '...']) &&
        Fast.match?(ast, [[:op_asgn, '...']]) &&
        Fast.match?(ast, [:op_asgn, '_', '_', '_']) &&
        Fast.match?(ast, ['_', '_', :+, '_'])
      ).to be_truthy
      expect(Fast).not_to be_match(ast, ['_', '_', :-, '_'])
    end

    it 'can mix custom procs' do
      ast_int = s(:op_asgn, s(:lvasgn, :a), :+, s(:int, 1))
      ast_float = s(:op_asgn, s(:lvasgn, :a), :+, s(:float, 1.2))
      ast_str = s(:op_asgn, s(:lvasgn, :a), :+, s(:str, ""))
      int_or_float = -> (node) { [:int, :float].include?(node.type)} 

      expression = ['_', '_', :+, int_or_float ]
      expect(Fast.match?(ast_str, expression)).to be_falsey
      expect(Fast.match?(ast_int, expression)).to be_truthy
      expect(Fast.match?(ast_float, expression)).to be_truthy
    end

    it 'ignores empty spaces' do
      expect(
        Fast.match?(
          s(:send, s(:send, s(:send, nil, :a), :b), :c),
          '(send    (send    (send   nil   _)   _)   _)'
        )
      ).to be_truthy
    end

    context '`any`' do
      it 'allows us to see if any condition matches {}' do
        expect(Fast.match?(s(:float, 1.2), '{int float} _')).to be_truthy
        expect(Fast.match?(s(:int, 1), '{int float} _')).to be_truthy
        expect(Fast.match?(s(:str, "1.2"), '{int float} _')).to be_falsy
      end

      it 'works in nested levels' do
        expect(Fast.match?(s(:send, s(:float, 1.2), :+, s(:int, 1)), '(send ({int float} _) :+ (int _))')).to be_truthy
        expect(Fast.match?(s(:send, s(:int, 2), :+, s(:int, 5)), '(send ({int float} _) + (int _))')).to be_truthy
        expect(Fast.match?(s(:send, s(:int, 2), :+, s(:int, 5)), '(send ({int float} _) + (int _))')).to be_truthy
        expect(Fast.match?(s(:send, s(:int, 2), :-, s(:int, 5)), '(send ({int float} _) + (int _))')).to be_falsy
        expect(Fast.match?(s(:send, s(:int, 2), :-, s(:int, 5)), '(send ({int float} _) {+-} (int _))')).to be_truthy
      end

      it 'for symbols or expressions' do
        expect(Fast.match?(s(:send, s(:float, 1.2), :+, s(:int, 1)), '(send ({int float} _) :+ (int _))')).to be_truthy
      end
    end

    context '`all`' do
      it 'allows join expressions with `and`' do
        Fast.debug do
          expect(Fast.match?(s(:int, 3), '([!str !hash] _)')).to be_truthy
          expect(Fast.match?(s(:int, 3), '(int [!1 !2])')).to be_truthy
        end
      end
    end

    context '`not` negates with !' do
      specify do
        expect(Fast.match?(code["1.0"], '!(int _)')).to be_truthy
        expect(Fast.match?(code["1.0"], '!(float _)')).to be_falsy
        expect(Fast.match?(code[":sym"], '!({str int float} _)')).to be_truthy
        expect(Fast.match?(code["1"], '!({str int float} _)')).to be_falsy
      end
    end

    context '`maybe` do partial search with `?`' do
      specify do
        expect(Fast.match?(code["a.b"], '(send (send nil _) _)')).to be_truthy
        expect(Fast.match?(code["a.b"], '(send (send nil a) b)')).to be_truthy
        expect(Fast.match?(code["a.b"], '(send ?(send nil a) b)')).to be_truthy
        expect(Fast.match?(code["b"],   '(send ?(send nil a) b)')).to be_truthy
        expect(Fast.match?(code["b.a"], '(send ?(send nil a) b)')).to be_falsy
      end
    end

    context 'reuse elements captured previously in the search with `\\<capture-index>`' do
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

    context 'capture with `$`' do
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

    context '`Parent` can follow expression in children with `^`' do
      it "ignores type and search in children using expression following" do
        expect(Fast.match?(code["a = 1"], '^(int _)')).to be_truthy
      end

      it 'captures parent of parent and also ignore non node children' do
        ast = code["b = a = 1"]
        expect(Fast.match?(ast, '$^^(int _)')).to eq([ast])
      end
    end
  end

  context 'search in files' do
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
      result = Fast.search_file('$(ivar _ ...)', 'sample.rb')
      instance_variable_names = result.map(&:children).map(&:first)
      expect(instance_variable_names).to eq(%i[@lang @name])
    end

    specify do
      result = Fast.search_file('$(lvar _ ...)', 'sample.rb')
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

    context 'replace' do
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

  context 'debug' do
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

end
