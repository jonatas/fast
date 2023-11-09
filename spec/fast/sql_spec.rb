require 'spec_helper'

RSpec.shared_context :with_sql_file do
  let(:sql) { 'select * from my_table' }
  let(:file) { 'tmp.sql'}
  before :each do
    File.open(file, 'w') { |f| f.write(sql) }
  end
  after :each do
    File.delete(file) if File.exist?(file)
  end
end

RSpec.describe Fast do
  describe ".parse_sql" do
    let(:ast) { described_class.parse_sql(sql) }

    context "when query sql is a plain statement" do
      describe "integer" do
        let(:sql) { "select 1" }
        it do
          expect(ast).to eq(
              s(:select_stmt,
                s(:target_list,
                  s(:res_target,
                    s(:val,
                      s(:a_const,
                        s(:val,
                          s(:integer,
                            s(:ival, 1)))))))))
        end
      end
    end

    context "when query sql is a plain statement" do
      describe "integer" do
        let(:sql) { "select 1" }
        it "simplifies the AST" do
          expect(ast).to eq( s(:select_stmt,
                               s(:target_list,
                                 s(:res_target,
                                   s(:val,
                                     s(:a_const,
                                       s(:val,
                                         s(:integer,
                                           s(:ival, 1)))))))))
        end
      end
      describe "string" do
        let(:sql) { "select 'hello'" }
        it do
          expect(ast).to eq(
            s(:select_stmt,
              s(:target_list,
                s(:res_target,
                  s(:val,
                    s(:a_const,
                      s(:val,
                        s(:string,
                          s(:str, "hello")))))))))
        end
      end
      describe "float" do
        let(:sql) { "select 1.0" }
        it do
          expect(ast).to eq(
            s(:select_stmt,
              s(:target_list,
                s(:res_target,
                  s(:val,
                    s(:a_const,
                      s(:val,
                        s(:float,
                          s(:str, "1.0")))))))))
        end
      end

      describe "array" do
        let(:sql) { "select array[1,2,3]" }
        it do
          expect(ast).to eq(
            s(:select_stmt,
              s(:target_list,
                s(:res_target,
                  s(:val,
                    s(:a_array_expr,
                      s(:elements,
                        s(:a_const,
                          s(:val,
                            s(:integer,
                              s(:ival, 1)))),
                        s(:a_const,
                          s(:val,
                            s(:integer,
                              s(:ival, 2)))),
                        s(:a_const,
                          s(:val,
                            s(:integer,
                              s(:ival, 3)))))))))))
        end
      end
    end

    context "when multiple queries are assigned" do
      let(:sql) { "select 1; select 2;" }
      specify do
        expect(ast).to eq([
          s(:select_stmt,
            s(:target_list,
              s(:res_target,
                s(:val,
                  s(:a_const,
                    s(:val,
                      s(:integer,
                        s(:ival, 1)))))))),
          s(:select_stmt,
            s(:target_list,
              s(:res_target,
                s(:val,
                  s(:a_const,
                    s(:val,
                      s(:integer,
                        s(:ival, 2))))))))])
      end
    end
    context "when use alias" do
      let(:sql) { "select 1 as a" }
      specify do
        expect(ast).to eq(
           s(:select_stmt,
         s(:target_list,
           s(:res_target,
             s(:name, "a"),
             s(:val,
               s(:a_const,
                 s(:val,
                   s(:integer,
                     s(:ival, 1)))))))))
      end
    end
    context "when use from" do
      let(:sql) { "select 1 from a" }
      specify do
        expect(ast).to eq(
          s(:select_stmt,
            s(:target_list,
              s(:res_target,
                s(:val,
                  s(:a_const,
                    s(:val,
                      s(:integer,
                        s(:ival, 1))))))),
            s(:from_clause,
              s(:range_var,
                s(:relname, "a"),
                s(:inh, true),
                s(:relpersistence, "p")))))
      end
    end

    context "when use group by" do
      let(:sql) { "select 1 from a group by 1" }
      specify do
        expect(ast).to eq(
          s(:select_stmt,
            s(:target_list,
              s(:res_target,
                s(:val,
                  s(:a_const,
                    s(:val,
                      s(:integer,
                        s(:ival, 1))))))),
          s(:from_clause,
            s(:range_var,
              s(:relname, "a"),
              s(:inh, true),
              s(:relpersistence, "p"))),
          s(:group_clause,
            s(:a_const,
              s(:val,
                s(:integer,
                  s(:ival, 1)))))))
      end
    end
  end

  describe ".match?" do
    let(:sql) { described_class.method(:parse_sql) }

    context "matches sql nodes" do
      specify "match Node Pattern" do
        expect(described_class).to be_match('(select_stmt ...)', sql['select 1'])
        expect(described_class).to be_match('(select_stmt (target_list (res_target (val (a_const (val (integer (ival 1))))))))',
                                             sql['select 1'])
      end

      specify "captures nodes" do
        expect(described_class.match?('(select_stmt (target_list (res_target (val (a_const (val (integer $(ival 1))))))))',
                                     sql['select 1']))
          .to eq([s(:ival, 1)])
      end

      specify "captures multiple nodes" do
        columns_and_table = <<~PATTERN
            (select_stmt
              (target_list (res_target (val (column_ref (fields $...)))))
              (from_clause (range_var $(relname _))))
          PATTERN

        expect(
          described_class.capture(
            columns_and_table,
            sql['select name from customer']
          )).to eq([
            s(:string, s(:str, "name")),
            s(:relname, "customer")])
      end
    end

    describe "location" do
      specify "loads source from expression range" do
        ast = described_class.parse_sql(sql='select name, address from customer')
        range_from = -> (element){ ast.search(element).map{|e|e.location.expression }}
        source_from = -> (element){ ast.search(element).map{|e|e.location.expression.source}}

        expect(source_from["select_stmt"]).to eq([sql])
        expect(source_from["relname"]).to eq(["customer"])
        expect(range_from["relname"].map(&:to_range)).to eq([26...34])
        expect(source_from["fields"]).to eq(["name", "address"])
        expect(range_from["fields"].map(&:to_range)).to eq([7...11, 13...20])
      end
    end
  end

  describe '.replace_sql' do
    subject { described_class.replace_sql(expression, ast, &replacement) }

    context 'with ival' do
     let(:expression) {'(ival _)'}
      let(:ast) { Fast.parse_sql('select 1') }
      let(:replacement) { ->(node) { replace(node.location.expression, '2') } }

      it { is_expected.to eq 'select 2' }
    end

    context 'with relname' do
     let(:expression) {'(relname _)'}
      let(:ast) { Fast.parse_sql('select * from wrong_table') }
      let(:replacement) { ->(node) { replace(node.location.expression, 'right_table') } }

      it { is_expected.to eq 'select * from right_table' }
    end
  end

  describe '.parse_sql_file' do
    include_context :with_sql_file

    subject(:ast) { described_class.parse_sql_file(file) }

    specify do
      expect(ast).to be_a Fast::Node
      expect(ast.type).to eq(:select_stmt)
    end
  end

  describe '.replace_file' do
    include_context :with_sql_file

    context 'when update from statement' do
      let(:pattern) {'relname'}
      let(:replacement) { ->(node) { replace(node.location.expression, 'other_table') } }

      specify do
        expect { described_class.replace_sql_file('relname', file, &replacement) }
          .to change { IO.read(file) }
          .from("select * from my_table")
          .to("select * from other_table")
      end
    end

    context 'when update from statement in middle of comments' do
      let(:sql) { <<~SQL }
      -- comment
      select * from my_table
      -- comment 2
      SQL

      let(:pattern) {'relname'}
      let(:replacement) { ->(node) { replace(node.location.expression, 'other_table') } }

      specify do
        expect { described_class.replace_sql_file('relname', file, &replacement) }
          .to change { IO.read(file) }
          .from(sql)
          .to(<<~SQL.chomp)
            -- comment
            select * from other_table
            -- comment 2
            SQL
      end
    end
  end
end
