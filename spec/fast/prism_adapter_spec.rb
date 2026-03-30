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
