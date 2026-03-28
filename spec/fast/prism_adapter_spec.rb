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
  end
end

RSpec.describe Fast do
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
