require 'spec_helper'

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
                      s(:ival,
                        s(:ival, 1))))))))
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
                                       s(:ival,
                                         s(:ival, 1))))))))
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
                      s(:sval,
                        s(:sval, "hello"))))))))
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
                      s(:fval,
                        s(:fval, "1.0"))))))))
        end
      end
    end

    context "when multiple queries are assigned" do
      let(:sql) { "select 1; select 2;" }
      specify do
        expect(ast).to eq([Fast.parse_sql("select 1"), Fast.parse_sql("select 2")])
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
                 s(:ival,
                   s(:ival, 1))))))))
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
                    s(:ival,
                      s(:ival, 1)))))),
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
                    s(:ival,
                      s(:ival, 1)))))),
          s(:from_clause,
            s(:range_var,
              s(:relname, "a"),
              s(:inh, true),
              s(:relpersistence, "p"))),
          s(:group_clause,
            s(:a_const,
              s(:ival,
                s(:ival, 1))))))
      end
    end
  end

  describe ".match?" do
    let(:sql) { described_class.method(:parse_sql) }

    context "matches sql nodes" do
      specify "match Node Pattern" do
        expect(described_class).to be_match('(select_stmt ...)', sql['select 1'])
      end

      specify "captures nodes" do
        expect(described_class.match?('(select_stmt (target_list (res_target (val (a_const (ival (ival $_))))))))', sql['select 1'])).to eq([1])
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
            s(:string, s(:sval, "name")),
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

      specify "multiple statements" do
        ast = described_class.parse_sql(sql='drop table a;drop table b;drop table c;')
        expect(Fast.search("drop_stmt", ast).map(&:source)).to eq(["drop table a","drop table b","drop table c"])
      end
    end
  end

  describe "node replacement" do
    let(:ast) { Fast.parse_sql('select 1')}

    it "works with string replacement searching for a pattern" do
      expect(ast.replace("ival", "2")).to eq('select 2')
    end

    it "works with replacement" do
      add_comment = ->{insert_before(_1.loc.expression,"-- my query\n")}
      expect(ast.replace('target_list', &add_comment)).to eq("-- my query\nselect 1")
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
          .to(<<~SQL)
            -- comment
            select * from other_table
            -- comment 2
            SQL
      end
    end
    context 'when has multiple statements' do
      let(:sql) { <<~SQL }
      select * from a;
      select * from b;
      SQL

      let(:pattern) {'(relname "a")'}
      let(:replacement) { ->(node, i) { replace(node.location.expression, 'c') } }

      specify do
        expect { described_class.replace_sql_file('relname', file, &replacement) }
          .to change { IO.read(file) }
          .from(sql)
          .to(<<~SQL)
            select * from c;
            select * from b;
            SQL
      end
    end
  end
end
