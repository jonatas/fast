require "spec_helper"

RSpec.describe Fast do

  let(:f) { -> (arg) { Fast::Find.new(arg) } }
  let(:c) { -> (arg) { Fast::Capture.new(arg) } }

  def s(type, *children)
    Parser::AST::Node.new(type, children)
  end

  it "has a version number" do
    expect(Fast::VERSION).not_to be nil
  end

  let(:defined_proc) { described_class::LITERAL }

  context '.expression' do
    it 'wraps the searching array' do
      expect(Fast.expression('...')).to eq([f[defined_proc['...']]])
      expect(Fast.expression('...')).to all(be_a(Fast::Find))
      expect(Fast.expression('$...')).to all(be_a(Fast::Capture))
    end

    it 'wraps the searching into an array' do
      expect(Fast.expression('send ...')).to eq([f[:send], f[defined_proc['...']]])
      expect(Fast.expression(':send ...')).to eq([f[:send], f[defined_proc['...']]])
      expect(Fast.expression('(send (send nil :a) :b)')).to eq([f[:send], [f[:send], f[nil], f[:a]], f[:b]])
      expect(Fast.expression('(send (send (send nil :a) :b) :c)')).to eq([f[:send], [f[:send], [f[:send], f[nil], f[:a]], f[:b]], f[:c]])
    end

    it 'captures in multiple levels' do
      expect(Fast.expression('send $...')).to eq([f[:send], c[defined_proc['...']]])
      expect(Fast.expression('send $...')).not_to eq([c[:send], c[defined_proc['...']]])
      expect(Fast.expression('(send (send nil $:a) :b)')).to eq([f[:send], [f[:send], f[nil], c[:a]], f[:b]])
      expect(Fast.expression('(send $(send nil :a) :b)')).to eq([f[:send], [c[:send], f[nil], f[:a]], f[:b]])
    end
  end

  it 'parse pre-defined literals into procs' do
    expect(Fast.parse(['...'])).to eq([f[defined_proc['...']]])
    expect(Fast.parse([1,'_'])).to eq([f[1], f[defined_proc['_']]])
  end

  it 'matches ast code' do
    expect(Fast.match?(s(:int, 1), ['...'])).to be_truthy
  end

  it 'matches ast code literal' do
    expect(Fast.match?(s(:int, 1), [:int, 1])).to be_truthy
    expect(Fast.match?(s(:int, 1), [:int, 1])).to be_truthy
  end

  it 'matches ast deeply ' do
     ast = s(:op_asgn, s(:lvasgn, :a), :+, s(:int, 1))
     expect(Fast.match?(ast, [:op_asgn, '...'])).to be_truthy
     expect(Fast.match?(ast, [:op_asgn, '_', '_', '_'])).to be_truthy
     expect(Fast.match?(ast, ['_', '_', :+, '_'])).to be_truthy
  end

  it 'matches with custom procs' do
     ast_int = s(:op_asgn, s(:lvasgn, :a), :+, s(:int, 1))
     ast_float = s(:op_asgn, s(:lvasgn, :a), :+, s(:float, 1.2))
     ast_str = s(:op_asgn, s(:lvasgn, :a), :+, s(:str, ""))

     expression = ['_', '_', :+, -> (node) { [:int, :float].include?(node.type)} ]
     expect(Fast.match?(ast_str, expression)).to be_falsey
     expect(Fast.match?(ast_int, expression)).to be_truthy
     expect(Fast.match?(ast_float, expression)).to be_truthy
  end

  it 'navigates deeply' do
    ast = s(:send, s(:send, s(:send, nil, :a), :b), :c)
    expression = '(send (send (send nil $_) $_) $_)'
    expect(Fast.match?(ast, expression)).to eq([:a,:b,:c])
  end

  it 'captures deeply' do
    ast = s(:send, s(:send, nil, :a), :b)
    capture_node = '(send $(send nil :a) :b)'
    expect(Fast.match?(ast, capture_node).first).to eq(ast.children.first)
  end

  it 'captures multiple' do
   expect(
     Fast.match?(
       s(:send, s(:int, 1), :+, s(:int, 2)),
       '(:send $(:int _) :+ $(:int _))'
     )).to eq [s(:int, 1), s(:int, 2)]
  end
end
