# frozen_string_literal: true

require 'spec_helper'
require 'fast/source'

RSpec.describe Fast::Source do
  describe '.buffer' do
    it 'builds a source buffer with content' do
      buffer = described_class.buffer('(string)', source: 'hello')

      expect(buffer).to be_a(Fast::Source::Buffer)
      expect(buffer.source).to eq('hello')
      expect(buffer.name).to eq('(string)')
    end
  end

  describe '.range' do
    it 'builds a range from a buffer' do
      buffer = described_class.buffer('(string)', source: 'hello')
      range = described_class.range(buffer, 1, 4)

      expect(range).to be_a(Fast::Source::Range)
      expect(range.source).to eq('ell')
    end
  end

  describe '.map' do
    it 'builds a source map from a range' do
      buffer = described_class.buffer('(string)', source: 'hello')
      range = described_class.range(buffer, 0, 5)
      map = described_class.map(range)

      expect(map).to be_a(Fast::Source::Map)
      expect(map.expression.source).to eq('hello')
    end
  end
end
