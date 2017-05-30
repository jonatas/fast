require "spec_helper"

RSpec.describe Fast do

  let(:f) { -> (arg) { Fast::Find.new(arg) } }
  let(:c) { -> (arg) { Fast::Capture.new(arg) } }
  let(:union) { -> (arg) { Fast::Union.new(arg) } }
  let(:defined_proc) { described_class::LITERAL }

  def s(type, *children)
    Parser::AST::Node.new(type, children)
  end

  context '.expression' do
    it 'from simple string' do
      expect(Fast.expression('...')).to be_a(Fast::Find)
      expect(Fast.expression('$...')).to be_a(Fast::Capture)
      expect(Fast.expression('{}')).to be_a(Fast::Union)
    end

    it 'allows proc shortcuts' do
      expect(Fast.expression('...')).to eq(f[defined_proc['...']])
      expect(Fast.expression('_')).to eq(f[defined_proc['_']])
    end

    it 'ignore semicolon' do
      expect(Fast.expression(':send')).to eq(Fast.expression('send'))
    end

    it 'ignore empty spaces' do
      expect(Fast.expression('(send     (send     nil                   _)                    _)'))
                    .to eq([f[:send],[f[:send], f[nil], f[defined_proc['_']]],f[defined_proc['_']]])
    end

    it 'wraps expressions deeply' do
      expect(Fast.expression('(send (send nil a) b)')).to eq([f[:send], [f[:send], f[nil], f[:a]], f[:b]])
      expect(Fast.expression('(send (send (send nil a) b) c)')).to eq([f[:send], [f[:send], [f[:send], f[nil], f[:a]], f[:b]], f[:c]])
    end

    context 'union sequence' do
      specify do
        expect(
          Fast.expression(
            '(:send $({:int :float} _) :+ $(:int _))'
          )
        ).to eq(
          [
            f[:send],
            c[
              [
                union[[f[:int], f[:float]]],
                f[defined_proc['_']]
              ]
            ], f[:+],
            c[
              [
                f[:int],
                f[defined_proc['_']]
              ]
            ]
          ])
      end
    end

    context 'capture with $' do
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

      it 'expressions deeply' do
        expect(Fast.expression('(send (send nil a) b)')).to eq([f[:send], [f[:send], f[nil], f[:a]], f[:b]])
        expect(Fast.expression('(send (send (send nil a) b) c)')).to eq([f[:send], [f[:send], [f[:send], f[nil], f[:a]], f[:b]], f[:c]])
      end

      it 'multiple levels' do
        expect(Fast.expression('(send (send nil $:a) :b)')).to eq([f[:send], [f[:send], f[nil], c[f[:a]]], f[:b]])
        expect(Fast.expression('(send $(send nil :a) :b)')).to eq([f[:send], c[[f[:send], f[nil], f[:a]]], f[:b]])
      end
    end
  end

  describe '.parse' do
    context 'pre process arrays' do
      it 'converts everything to a find' do
        expect(Fast.parse([1])).to eq([f[1]])
        expect(Fast.parse([:sym])).to eq([f[:sym]])
        expect(Fast.parse(['sym'])).to eq([f[:sym]])
      end

      it '... and _ into pre-defined procs' do
        expect(Fast.parse(['...'])).to eq([f[defined_proc['...']]])
        expect(Fast.parse([1,'_'])).to eq([f[1], f[defined_proc['_']]])
      end

      it 'nil into nil' do
        expect(Fast.parse([nil])).to eq([f[nil]])
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
      expect(Fast.match?(s(:int, 1), '...')).to be_truthy
      expect(Fast.match?(s(:int, 1), '_ _')).to be_truthy
    end

    it 'matches ast code literal' do
      expect(Fast.match?(s(:int, 1), [:int, 1])).to be_truthy
    end

    it 'matches ast deeply ' do
      ast = s(:op_asgn, s(:lvasgn, :a), :+, s(:int, 1))
      expect(Fast.match?(ast, [:op_asgn, '...'])).to be_falsy
      expect(Fast.match?(ast, [:op_asgn, '...', '_', '...'])).to be_truthy
      expect(Fast.match?(ast, [[:op_asgn, '...']])).to be_truthy
      expect(Fast.match?(ast, [:op_asgn, '_', '_', '_'])).to be_truthy
      expect(Fast.match?(ast, ['_', '_', :+, '_'])).to be_truthy
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

    context 'union sequence' do
      it 'allows us to join conditions using {}' do
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
  end
end
