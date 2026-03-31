# frozen_string_literal: true

require 'spec_helper'
require 'fast/prism_adapter'

RSpec.describe Fast::PrismAdapter do
  describe '.parse' do
    let(:source) do
      <<~RUBY
        class ModernController
          include Trackable
          before_action :load_user, if: :current_user?

          def analytics(scope)
            payload = {scope:, enabled: true}
          end
        end
      RUBY
    end

    it 'produces a tree that works with Fast.search' do
      tree = described_class.parse(source)

      expect(Fast.search('(class ...)', tree).map(&:type)).to eq([:class])
      expect(Fast.search('(send nil include (const nil Trackable))', tree).map(&:type)).to eq([:send])
      expect(Fast.search('(def analytics)', tree).map(&:type)).to eq([:def])
    end

    it 'adapts singleton methods, blocks, floats, embedded variables, and keyword args' do
      source = <<~'RUBY'
        class ModernController
          class << self
            def build(rate:, enabled: true, **options)
              transform(1.5) { |value| "#{value}" }
            end
          end
        end
      RUBY

      tree = described_class.parse(source)

      expect(Fast.search('(sclass _ _)', tree).map(&:type)).to eq([:sclass])
      expect(Fast.search('(def build)', tree).map(&:type)).to eq([:def])
      expect(Fast.search('(float 1.5)', tree).map(&:type)).to eq([:float])
      expect(Fast.search('(block _ _ _)', tree).map(&:type)).to eq([:block])
      expect(Fast.search('(dstr ...)', tree).map(&:type)).to eq([:dstr])
      expect(Fast.search('(kwarg rate)', tree).map(&:type)).to eq([:kwarg])
      expect(Fast.search('(kwoptarg enabled (true))', tree).map(&:type)).to eq([:kwoptarg])
      expect(Fast.search('(kwrestarg _)', tree).map(&:type)).to eq([:kwrestarg])
    end

    it 'adapts block-pass call arguments used by &:method shorthand' do
      tree = described_class.parse('items.map(&:source)')

      expect(Fast.search('(send (send nil items) map (block_pass (sym source)))', tree).map(&:type)).to eq([:send])
    end

    it 'adapts case else branches through consequent fallback' do
      source = <<~'RUBY'
        class Greeter
          def call(language)
            case language
            when :pt
              :ola
            else
              helper { |value| "#{value}" }
            end
          end
        end
      RUBY

      tree = described_class.parse(source)

      expect(Fast.search('(case ...)', tree).map(&:type)).to eq([:case])
      expect(Fast.search('(when ...)', tree).map(&:type)).to eq([:when])
      expect(Fast.search('(block ...)', tree).map(&:type)).to eq([:block])
      expect(Fast.capture('$(dstr _)', tree).map(&:loc).map { |loc| loc.expression.source })
        .to eq(['"#{value}"'])
      end

      it 'adapts loops and multiple assignments' do
      source = <<~RUBY
        while a; b; end
        until c; d; end
        for i in items; j; end
        x, y = 1, 2
      RUBY

      tree = described_class.parse(source)

      expect(Fast.search('(while (send nil a) (send nil b))', tree)).not_to be_empty
      expect(Fast.search('(until (send nil c) (send nil d))', tree)).not_to be_empty
      expect(Fast.search('(for (lvasgn i) (send nil items) (send nil j))', tree)).not_to be_empty
      expect(Fast.search('(masgn (mlhs (lvasgn x) (lvasgn y)) (array (int 1) (int 2)))', tree)).not_to be_empty
      end

      it 'adapts control flow and execution blocks' do
      source = <<~RUBY
        redo
        retry
        BEGIN { 1 }
        END { 2 }
      RUBY

      tree = described_class.parse(source)

      expect(Fast.search('(redo)', tree)).not_to be_empty
      expect(Fast.search('(retry)', tree)).not_to be_empty
      expect(Fast.search('(preexe (int 1))', tree)).not_to be_empty
      expect(Fast.search('(postexe (int 2))', tree)).not_to be_empty
      end

    it 'adapts special references and literals' do
      source = <<~RUBY
        $1
        $&
        1r
        1i
      RUBY

      tree = described_class.parse(source)

      expect(Fast.search('(nth_ref 1)', tree)).not_to be_empty
      expect(Fast.search('(back_ref :$&)', tree)).not_to be_empty
      expect(Fast.search('(rational _)', tree)).not_to be_empty
      expect(Fast.search('(complex _)', tree)).not_to be_empty
    end

      it 'adapts regex matching constructs' do
      source = <<~RUBY
        /(?<a>)/ =~ b
        if /a/; end
      RUBY

      tree = described_class.parse(source)

      expect(Fast.search('(match_with_lvasgn (regexp (str "(?<a>)") (regopt)) (send nil b))', tree)).not_to be_empty
      expect(Fast.search('(if (match_current_line (regexp (str a) (regopt))) nil nil)', tree)).not_to be_empty
      end
      end
      end

RSpec.describe Fast do
  describe '.ast' do
    it 'uses the Prism-backed path by default' do
      source = <<~RUBY
        class ModernController
          def analytics(scope)
            payload = {scope:, enabled: true}
          end
        end
      RUBY

      tree = described_class.ast(source)

      expect(Fast.search('(class ...)', tree).map(&:type)).to eq([:class])
      expect(Fast.search('(def analytics)', tree).map(&:type)).to eq([:def])
    end
  end

  describe '.parse_ruby' do
    it 'falls back to Prism and still supports Fast.search' do
      source = <<~RUBY
        class ModernController
          include Trackable

          def analytics(scope)
            payload = {scope:, enabled: true}
          end
        end
      RUBY

      tree = described_class.parse_ruby(source)

      expect(Fast.search('(class ...)', tree).map(&:type)).to eq([:class])
      expect(Fast.search('(send nil include (const nil Trackable))', tree).map(&:type)).to eq([:send])
      expect(Fast.search('(def analytics)', tree).map(&:type)).to eq([:def])
    end
  end
end
