require "spec_helper"

RSpec.describe Fast do

  def s(type, *children)
    Parser::AST::Node.new(type, children)
  end

  it "has a version number" do
    expect(Fast::VERSION).not_to be nil
  end

  let(:defined_proc) { described_class::LITERAL }


  it 'parse pre-defined literals into procs' do
    expect(Fast.parse(['...'])).to eq([defined_proc['...']])
    expect(Fast.parse([1,'_'])).to eq([1, defined_proc['_']])
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

  it 'matches with captures' do
    ast =
      s(:send,
        s(:send,
          s(:send,
            s(:send, nil, :a),
            :b),
          :c),
        :d)

     expect(Fast.match?(ast, [:send, '...'])).to be_truthy
     expect(Fast.match?(ast, [:send, [:send, '...'], :d])).to be_truthy
     expect(Fast.match?(ast, [:send, [:send, '...'], :c])).to be_falsy
     expect(Fast.match?(ast, [:send, [:send, [:send, '...'], :c], :d])).to be_truthy
     expect(Fast.match?(ast, [:send, [:send, [:send, [:send, nil, :a], :b], :c], :d])).to be_truthy
     expect(Fast.match?(ast, [:send, [:send, [:send, [:send, nil, '_'], '_'], :c], '_'])).to be_truthy
  end
end
