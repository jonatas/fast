# frozen_string_literal: true

require_relative 'source'

module Fast
  class SourceRewriter
    Edit = Struct.new(:kind, :begin_pos, :end_pos, :content, :order, keyword_init: true)
    ClobberingError = Class.new(StandardError)

    attr_reader :source_buffer

    def initialize(source_buffer)
      @source_buffer = source_buffer
      @edits = []
      @order = 0
    end

    def replace(range, content)
      add_edit(:replace, range, content.to_s)
      self
    end

    def remove(range)
      replace(range, '')
    end

    def wrap(range, before, after)
      insert_before(range, before) unless before.nil?
      insert_after(range, after) unless after.nil?
      self
    end

    def insert_before(range, content)
      add_edit(:insert_before, range.begin, content.to_s)
      self
    end

    def insert_after(range, content)
      add_edit(:insert_after, range.end, content.to_s)
      self
    end

    def process
      source = source_buffer.source.to_s
      normalized_replacements = normalize_replacements
      return source if normalized_replacements.empty? && insertions.empty?

      before_insertions = build_insertions(:insert_before)
      after_insertions = build_insertions(:insert_after)

      result = +''
      cursor = 0

      normalized_replacements.each do |replacement|
        result << emit_unreplaced_segment(source, cursor, replacement.begin_pos, before_insertions, after_insertions)
        result << before_insertions.fetch(replacement.begin_pos, '')
        result << replacement.content
        result << after_insertions.fetch(replacement.end_pos, '')
        cursor = replacement.end_pos
      end

      result << emit_unreplaced_segment(source, cursor, source.length, before_insertions, after_insertions)
      result
    end

    private

    attr_reader :edits

    def add_edit(kind, range, content)
      edits << Edit.new(
        kind: kind,
        begin_pos: range.begin_pos,
        end_pos: range.end_pos,
        content: content,
        order: next_order
      )
    end

    def next_order
      @order += 1
    end

    def insertions
      edits.select { |edit| insertion?(edit) }
    end

    def replacements
      edits.reject { |edit| insertion?(edit) }
    end

    def insertion?(edit)
      edit.kind == :insert_before || edit.kind == :insert_after
    end

    def normalize_replacements
      replacements
        .sort_by { |edit| [edit.begin_pos, edit.end_pos, edit.order] }
        .each_with_object([]) do |edit, normalized|
          previous = normalized.last
          if previous && overlaps?(previous, edit)
            if deletion?(previous) && deletion?(edit)
              previous.end_pos = [previous.end_pos, edit.end_pos].max
            elsif same_range?(previous, edit)
              previous.content = edit.content
              previous.order = edit.order
            else
              raise ClobberingError, "Overlapping rewrite on #{edit.begin_pos}...#{edit.end_pos}"
            end
          else
            normalized << edit.dup
          end
        end
    end

    def overlaps?(left, right)
      left.begin_pos < right.end_pos && right.begin_pos < left.end_pos
    end

    def same_range?(left, right)
      left.begin_pos == right.begin_pos && left.end_pos == right.end_pos
    end

    def deletion?(edit)
      edit.content.empty?
    end

    def build_insertions(kind)
      edits
        .select { |edit| edit.kind == kind }
        .group_by(&:begin_pos)
        .transform_values do |position_edits|
          position_edits
            .sort_by(&:order)
            .map(&:content)
            .join
        end
    end

    def emit_unreplaced_segment(source, from, to, before_insertions, after_insertions)
      segment = +''
      cursor = from

      while cursor < to
        segment << before_insertions.fetch(cursor, '')
        segment << source[cursor]
        cursor += 1
        segment << after_insertions.fetch(cursor, '')
      end
      segment
    end
  end
end
