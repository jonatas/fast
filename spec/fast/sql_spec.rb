require 'spec_helper'

RSpec.describe Fast do
  describe ".parse_sql" do
    let(:ast) { described_class.parse_sql(sql) }
    context "when sql is nil" do
      let(:sql) { nil }
      it { expect(ast).to eq([]) }
    end

    context "when query sql is a plain statement" do
      describe "integer" do
        let(:sql) { "select 1" }
        it do
          expect(ast).to eq(s(:select, s(:integer, 1)))
        end
      end
      describe "string" do
        let(:sql) { "select 'hello'" }
        it do
          expect(ast).to eq(s(:select, s(:string, "hello")))
        end
      end
      describe "float" do
        let(:sql) { "select 1.0" }
        it do
          expect(ast).to eq(s(:select, s(:float, 1.0)))
        end
      end

      describe "array" do
        let(:sql) { "select array[1,2,3]" }
        it do
          expect(ast).to eq(s(:select, s(:array, [s(:integer, 1), s(:integer, 2), s(:integer, 3)])))
        end
      end
    end

    context "when multiple queries are assigned" do
      let(:sql) { "select 1; select 2;" }
      specify do
        expect(ast).to eq([
          s(:select, s(:integer, 1)),
          s(:select, s(:integer, 2))
        ])
      end
    end
  end
end
