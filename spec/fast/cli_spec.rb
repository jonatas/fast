# frozen_string_literal: true

require 'spec_helper'
require 'fast/cli'

RSpec.describe Fast::Cli do
  describe '.initialize' do
    subject(:cli) { described_class.new args }

    context 'with --pry' do
      let(:args) { %w[--pry] }

      its(:pry) { is_expected.to be_truthy }
    end

    context 'with --debug' do
      let(:args) { %w[--debug] }

      it { is_expected.to be_debug_mode }
    end

    context 'with --similar' do
      let(:args) { %w[1.1 --similar] }

      its(:similar) { is_expected.to be_truthy }
      its(:pattern) { is_expected.to eq('(float _)') }
    end

    context 'with --ast' do
      let(:args) { %w[--ast] }

      its(:show_sexp) { is_expected.to be_truthy }
    end

    context 'with --code' do
      let(:args) { %w[1.1 --code] }

      its(:from_code) { is_expected.to be_truthy }
      its(:pattern) { is_expected.to eq('(float 1.1)') }
    end
  end
end
