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

    describe '#replace', only: :local do
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
        expect(File).to be_exist(spec)
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

    describe '#run_partial_replacement_with' do
      it 'tracks failed combinations when the policy rejects the rewrite' do
        allow(experiment.ok_if).to receive(:call).and_return(false)

        expect do
          experiment_file.run_partial_replacement_with(1)
        end.to output(/🔴/).to_stdout

        expect(experiment_file.fail_experiments).to include(1)
      end

      it 'raises when no changes were made' do
        allow(experiment_file).to receive(:partial_replace).and_return(File.read(spec))

        expect do
          experiment_file.run_partial_replacement_with(1)
        end.to raise_error('No changes were made to the file.')
      end
    end

    describe '#done!' do
      it 'prints completion details and applies the winning experimental file' do
        experiment_file.ok_with([1, 3])
        winning_file = experiment_file.experimental_filename([1, 3])
        File.write(winning_file, "let(:user) { build_stubbed(:user) }\n")

        expect do
          experiment_file.done!
        end.to output(/Done with .* after 1 combinations.*mv .*#{Regexp.escape(winning_file)}.*/m).to_stdout

        expect(File.read(spec)).to eq("let(:user) { build_stubbed(:user) }\n")
      ensure
        File.delete(winning_file) if winning_file && File.exist?(winning_file)
      end

      it 'removes generated files when autoclean is enabled' do
        experiment.autoclean = true
        experiment_file.ok_with([1, 3])
        winning_file = experiment_file.experimental_filename([1, 3])
        stale_file = experiment_file.experimental_filename([2])
        File.write(winning_file, "let(:user) { build_stubbed(:user) }\n")
        File.write(stale_file, "stale\n")

        experiment_file.done!

        expect(File).not_to exist(winning_file)
        expect(File).not_to exist(stale_file)
      end
    end

    describe '#run' do
      it 'skips files with too many combinations' do
        allow(experiment_file).to receive(:build_combinations).and_return((1..1001).to_a, [])
        allow(experiment_file).to receive(:done!)

        expect do
          experiment_file.run
        end.to output(/Ignoring .* because it has 1001 possible combinations/).to_stdout
      end

      it 'removes stale generated files before running when autoclean is enabled' do
        experiment.autoclean = true
        stale_file = experiment_file.experimental_filename([99])
        File.write(stale_file, "stale\n")
        allow(experiment_file).to receive(:build_combinations).and_return([])
        allow(experiment_file).to receive(:done!)

        experiment_file.run

        expect(File).not_to exist(stale_file)
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

  describe 'end-to-end policy run' do
    let(:tmpdir) { Dir.mktmpdir('fast_experiment_spec') }
    let(:spec_file) { File.join(tmpdir, 'replace_create_spec.rb') }

    before do
      File.write(spec_file, <<~RUBY)
        RSpec.describe 'experiment rewrite' do
          it 'passes only after rewriting' do
            expect(create(:user)).to eq(:ok)
          end
        end
      RUBY
    end

    after do
      FileUtils.remove_entry(tmpdir) if File.exist?(tmpdir)
    end

    it 'rewrites a failing spec into a passing one and applies the change' do
      target_file = spec_file
      experiment = Fast.experiment('RSpec/ReplaceCreateForTempSpec') do
        lookup target_file
        search '(send nil create)'
        edit { |node| replace(node.loc.expression, ':ok') }
        policy do |new_file|
          system("bundle exec rspec #{new_file} >/dev/null 2>&1")
        end
      end

      expect do
        experiment.run_with(target_file)
      end.to output(/✅ .*experiment_1_.*replace_create_spec\.rb/m).to_stdout

      expect(File.read(target_file)).to include('expect(:ok).to eq(:ok)')
    end
  end
end
