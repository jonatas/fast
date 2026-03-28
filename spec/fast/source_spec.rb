# frozen_string_literal: true

require 'spec_helper'
require 'fast/source'
require 'fast/source_rewriter'

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
      expect(range.line).to eq(1)
      expect(range.column).to eq(1)
      expect(range.to_range).to eq(1...4)
    end

    it 'tracks line information across multiple lines' do
      buffer = described_class.buffer('(string)', source: "one\ntwo\nthree")
      range = described_class.range(buffer, 4, 7)

      expect(range.first_line).to eq(2)
      expect(range.last_line).to eq(2)
      expect(range.column).to eq(0)
    end

    it 'joins adjacent ranges' do
      buffer = described_class.buffer('(string)', source: 'hello world')
      left = described_class.range(buffer, 0, 5)
      right = described_class.range(buffer, 6, 11)

      expect(left.join(right).source).to eq('hello world')
    end
  end

  describe '.map' do
    it 'builds a source map from a range' do
      buffer = described_class.buffer('(string)', source: 'hello')
      range = described_class.range(buffer, 0, 5)
      map = described_class.map(range)

      expect(map).to be_a(Fast::Source::Map)
      expect(map.expression.source).to eq('hello')
      expect(map.begin).to eq(0)
      expect(map.end).to eq(5)
      expect(map.with_expression(described_class.range(buffer, 1, 4)).expression.source).to eq('ell')
    end
  end

  describe '.parser_buffer' do
    it 'builds a parser-compatible buffer only for parser-backed paths' do
      buffer = described_class.parser_buffer('(string)', source: 'hello')

      expect(buffer.class.name).to eq('Parser::Source::Buffer')
      expect(buffer.source).to eq('hello')
    end
  end
end

RSpec.describe Fast::SourceRewriter do
  let(:buffer) { Fast::Source.buffer('(string)', source: source) }
  let(:rewriter) { described_class.new(buffer) }

  describe '#process' do
    let(:source) { 'hello world' }

    it 'replaces a range' do
      rewriter.replace(Fast::Source.range(buffer, 6, 11), 'reader')

      expect(rewriter.process).to eq('hello reader')
    end

    it 'inserts around a range' do
      range = Fast::Source.range(buffer, 6, 11)
      rewriter.insert_before(range, '(')
      rewriter.insert_after(range, ')')

      expect(rewriter.process).to eq('hello (world)')
    end

    it 'keeps later replacements on the same range' do
      range = Fast::Source.range(buffer, 6, 11)
      rewriter.replace(range, 'reader')
      rewriter.replace(range, 'friend')

      expect(rewriter.process).to eq('hello friend')
    end

    it 'merges overlapping deletions' do
      rewriter.remove(Fast::Source.range(buffer, 0, 5))
      rewriter.remove(Fast::Source.range(buffer, 3, 11))

      expect(rewriter.process).to eq('')
    end

    it 'raises on overlapping replacements' do
      rewriter.replace(Fast::Source.range(buffer, 0, 5), 'hi')
      rewriter.replace(Fast::Source.range(buffer, 3, 11), 'friend')

      expect { rewriter.process }.to raise_error(Fast::SourceRewriter::ClobberingError)
    end
  end
end
