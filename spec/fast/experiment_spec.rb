# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'fast/experiment'

RSpec.describe Fast::Experiment do
  subject(:experiment) do
    Fast.experiment('RSpec/ReplaceCreateWithBuildStubbed') do
      lookup 'some_spec.rb'
      search '(send nil create)'
      edit { |node| replace(node.loc.selector, 'build_stubbed') }
      policy { |new_file| system("bin/spring rspec --fail-fast #{new_file}") }
    end
  end

  describe Fast::ExperimentFile do
    let(:experiment_file) { Fast::ExperimentFile.new(spec, experiment) }
    let(:spec) do
      tempfile = Tempfile.new
      tempfile.write <<~RUBY
        let(:user) { create(:user) }
        let(:address) { create(:address) }
        let(:phone_number) { create(:phone_number) }
        let(:country) { create(:country) }
        let(:language) { create(:language) }
      RUBY
      tempfile.close
      tempfile.path
    end

    describe '#filename' do
      it { expect(experiment_file.experimental_filename(1)).to include('experiment_1') }
    end

    describe '#replace' do
      it 'replace only first case' do
        expect(experiment_file.partial_replace(1)).to eq(<<~RUBY)
          let(:user) { build_stubbed(:user) }
          let(:address) { create(:address) }
          let(:phone_number) { create(:phone_number) }
          let(:country) { create(:country) }
          let(:language) { create(:language) }
        RUBY
      end

      it 'replace only second case' do
        expect(File).to be_exists(spec)
        expect(experiment_file.partial_replace(2)).to eq(<<~RUBY)
          let(:user) { create(:user) }
          let(:address) { build_stubbed(:address) }
          let(:phone_number) { create(:phone_number) }
          let(:country) { create(:country) }
          let(:language) { create(:language) }
        RUBY
      end
    end

    describe '#build_combinations' do
      specify do
        # Replace each occurence individually.
        expect(experiment_file.build_combinations).to match_array([1, 2, 3, 4, 5])

        experiment_file.ok_with(1)
        experiment_file.failed_with(2)
        experiment_file.ok_with(3)
        experiment_file.ok_with(4)
        experiment_file.ok_with(5)

        # Try a combination of all OK individual replacements.
        expect(experiment_file.build_combinations).to match_array([[1, 3, 4, 5]])
        experiment_file.failed_with([1, 3, 4, 5])

        # If the above failed, divide and conquer.
        expect(experiment_file.build_combinations).to match_array([[1, 3], [1, 4], [1, 5], [3, 4], [3, 5], [4, 5]])

        experiment_file.ok_with([1, 3])
        experiment_file.failed_with([1, 4])

        expect(experiment_file.build_combinations).to eq([[4, 5], [1, 3, 4], [1, 3, 5]])

        experiment_file.failed_with([1, 3, 4])

        expect(experiment_file.build_combinations).to eq([[4, 5], [1, 3, 5]])

        experiment_file.failed_with([4, 5])

        expect(experiment_file.build_combinations).to eq([[1, 3, 5]])

        experiment_file.ok_with([1, 3, 5])

        expect(experiment_file.build_combinations).to be_empty
      end
    end
  end

  describe 'Fast.experiment' do
    subject(:experiment) do
      Fast.experiment('RSpec/ReplaceCreateWithBuildStubbed') do
        lookup 'spec/fast_spec.rb'
        search '(send nil create)'
        edit { |node| replace(node.loc.selector, 'build_stubbed') }
        policy { |new_file| system("bin/spring rspec --fail-fast #{new_file}") }
      end
    end

    it { is_expected.to be_a(described_class) }
    it { expect(experiment.name).to eq('RSpec/ReplaceCreateWithBuildStubbed') }
    it { expect(experiment.expression).to eq('(send nil create)') }
    it { expect(experiment.files_or_folders).to eq('spec/fast_spec.rb') }
    it { expect(experiment.replacement).to be_a(Proc) }

    specify do
      allow(experiment).to receive(:run_with).with('spec/fast_spec.rb') # rubocop:disable RSpec/SubjectStub
      experiment.run
    end

    it { is_expected.to eq(Fast.experiments['RSpec/ReplaceCreateWithBuildStubbed']) }
  end
end
