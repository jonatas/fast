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
end
