# frozen_string_literal: true

require 'fast'

# Allow to replace code managing multiple replacements and combining replacements.
# Useful for large codebase refactor and multiple replacements in the same file.
module Fast
  class << self
    # Fast.experiment is a shortcut to define new experiments and allow them to
    # work together in experiment combinations.
    #
    # The following experiment look into `spec` folder and try to remove
    # `before` and `after` blocks on testing code. Sometimes they're not
    # effective and we can avoid the hard work of do it manually.
    #
    # If the spec does not fail, it keeps the change.
    #
    # @example Remove useless before and after block
    #   Fast.experiment("RSpec/RemoveUselessBeforeAfterHook") do
    #     lookup 'spec'
    #     search "(block (send nil {before after}))"
    #     edit { |node| remove(node.loc.expression) }
    #     policy { |new_file| system("rspec --fail-fast #{new_file}") }
    #   end
    def experiment(name, &block)
      @experiments ||= {}
      @experiments[name] = Experiment.new(name, &block)
    end

    attr_reader :experiments
  end

  # Fast experiment allow the user to combine single replacements and make multiple
  # changes at the same time. Defining a policy is possible to check if the
  # experiment was successfull and keep changing the file using a specific
  # search.
  #
  # The experiment have a combination algorithm that recursively check what
  # combinations work with what combinations. It can delay years and because of
  # that it tries a first replacement targeting all the cases in a single file.
  #
  # You can define experiments and build experimental files to improve some code in
  # an automated way. Let's create a hook to check if a `before` or `after` block
  # is useless in a specific spec:
  #
  # @example Remove useless before or after block RSpec hooks
  #   #  Let's say you want to experimentally remove some before or after block
  #   #  in specs to check if some of them are weak or useless:
  #   #    RSpec.describe "something" do
  #   #      before { @a = 1 }
  #   #      before { @b = 1 }
  #   #      it { expect(@b).to be_eq(1) }
  #   #    end
  #   #
  #   #  The variable `@a` is not useful for the test, if I remove the block it
  #   #  should continue passing.
  #   #
  #   #    RSpec.describe "something" do
  #   #      before { @b = 1 }
  #   #      it { expect(@b).to be_eq(1) }
  #   #    end
  #   #
  #   #  But removing the next `before` block will fail:
  #   #    RSpec.describe "something" do
  #   #      before { @a = 1 }
  #   #      it { expect(@b).to be_eq(1) }
  #   #    end
  #   #  And the experiments will have a policy to check if `rspec` run without
  #   #  fail and only execute successfull replacements.
  #   Fast.experiment("RSpec/RemoveUselessBeforeAfterHook") do
  #     lookup 'spec' # all files in the spec folder
  #     search "(block (send nil {before after}))"
  #     edit {|node| remove(node.loc.expression) }
  #     policy {|new_file| system("rspec --fail-fast #{new_file}") }
  #   end
  #
  # @example Replace FactoryBot create with build_stubbed method
  #   # Let's say you want to try to automate some replacement of
  #   # `FactoryBot.create` to use `FactoryBot.build_stubbed`.
  #   # For specs let's consider the example we want to refactor:
  #   #   let(:person) { create(:person, :with_email) }
  #   # And the intent is replace to use `build_stubbed` instead of `create`:
  #   #   let(:person) { build_stubbed(:person, :with_email) }
  #   Fast.experiment('RSpec/ReplaceCreateWithBuildStubbed') do
  #     lookup 'spec'
  #     search '(block (send nil let (sym _)) (args) $(send nil create))'
  #     edit { |_, (create)| replace(create.loc.selector, 'build_stubbed') }
  #     policy { |new_file| system("rspec --format progress --fail-fast #{new_file}") }
  #   end
  # @see https://asciinema.org/a/177283
  class Experiment
    attr_writer :files
    attr_reader :name, :replacement, :expression, :files_or_folders, :ok_if

    def initialize(name, &block)
      @name = name
      puts "\nStarting experiment: #{name}"
      instance_exec(&block)
    end

    # It combines current experiment with {ExperimentFile#run}
    # @param [String] file to be analyzed by the experiment
    def run_with(file)
      ExperimentFile.new(file, self).run
    end

    # @param [String] expression with the node pattern to target nodes
    def search(expression)
      @expression = expression
    end

    # @param block yields the node that matches and return the block in the
    # instance context of a [Fast::Rewriter]
    def edit(&block)
      @replacement = block
    end

    # @param [String] files_or_folders that will be combined to find the {#files}
    def lookup(files_or_folders)
      @files_or_folders = files_or_folders
    end

    # It calls the block after the replacement and use the result
    # to drive the {Fast::ExperimentFile#ok_experiments} and {Fast::ExperimentFile#fail_experiments}.
    # @param block yields a temporary file with the content replaced in the current round.
    def policy(&block)
      @ok_if = block
    end

    # @return [Array<String>] with files from {#lookup} expression.
    def files
      @files ||= Fast.ruby_files_from(@files_or_folders)
    end

    # Iterates over all {#files} to {#run_with} them.
    # @return [void]
    def run
      files.map(&method(:run_with))
    end
  end

  # Suggest possible combinations of occurrences to replace.
  #
  # Check for {#generate_combinations} to understand the strategy of each round.
  class ExperimentCombinations
    attr_reader :combinations

    def initialize(round:, occurrences_count:, ok_experiments:, fail_experiments:)
      @round = round
      @ok_experiments = ok_experiments
      @fail_experiments = fail_experiments
      @occurrences_count = occurrences_count
    end

    # Generate different combinations depending on the current round.
    # * Round 1: Use {#individual_replacements}
    # * Round 2: Tries {#all_ok_replacements_combined}
    # * Round 3+: Follow {#ok_replacements_pair_combinations}
    def generate_combinations
      case @round
      when 1
        individual_replacements
      when 2
        all_ok_replacements_combined
      else
        ok_replacements_pair_combinations
      end
    end

    # Replace a single occurrence at each iteration and identify which
    # individual replacements work.
    def individual_replacements
      (1..@occurrences_count).to_a
    end

    # After identifying all individual replacements that work, try combining all
    # of them.
    def all_ok_replacements_combined
      [@ok_experiments.uniq.sort]
    end

    # Divide and conquer combining all successful individual replacements.
    def ok_replacements_pair_combinations
      @ok_experiments
        .combination(2)
        .map { |e| e.flatten.uniq.sort }
        .uniq - @fail_experiments - @ok_experiments
    end
  end

  # Combines an {Fast::Experiment} with a specific file.
  # It coordinates and regulate multiple replacements in the same file.
  # Everytime it {#run} a file, it uses {#partial_replace} and generate a
  # new file with the new content.
  # It executes the {Fast::Experiment#policy} block yielding the new file. Depending on the
  # policy result, it adds the occurrence to {#fail_experiments} or {#ok_experiments}.
  # When all possible occurrences are replaced in isolated experiments, it
  # #{build_combinations} with the winner experiments going to a next round of experiments
  # with multiple partial replacements until find all possible combinations.
  # @note it can easily spend days handling multiple one to one combinations,
  #   because of that, after the first round of replacements the algorithm goes
  #   replacing all winner solutions in the same shot. If it fails, it goes
  #   combining one to one.
  # @see Fast::Experiment
  # @example Temporary spec to analyze
  #   tempfile = Tempfile.new('some_spec.rb')
  #   tempfile.write <<~RUBY
  #     let(:user) { create(:user) }
  #     let(:address) { create(:address) }
  #     let(:phone_number) { create(:phone_number) }
  #     let(:country) { create(:country) }
  #     let(:language) { create(:language) }
  #   RUBY
  #   tempfile.close
  # @example Temporary experiment to replace create with build stubbed
  #   experiment = Fast.experiment('RSpec/ReplaceCreateWithBuildStubbed') do
  #     lookup 'some_spec.rb'
  #     search '(send nil create)'
  #     edit { |node| replace(node.loc.selector, 'build_stubbed') }
  #     policy { |new_file| system("rspec --fail-fast #{new_file}") }
  #   end
  # @example ExperimentFile exploring combinations and failures
  #   experiment_file = Fast::ExperimentFile.new(tempfile.path, experiment)
  #   experiment_file.build_combinations # => [1, 2, 3, 4, 5]
  #   experiment_file.ok_with(1)
  #   experiment_file.failed_with(2)
  #   experiment_file.ok_with(3)
  #   experiment_file.ok_with(4)
  #   experiment_file.ok_with(5)
  #   # Try a combination of all OK individual replacements.
  #   experiment_file.build_combinations # => [[1, 3, 4, 5]]
  #   experiment_file.failed_with([1, 3, 4, 5])
  #   # If the above failed, divide and conquer.
  #   experiment_file.build_combinations # => [[1, 3], [1, 4], [1, 5], [3, 4], [3, 5], [4, 5]]
  #   experiment_file.ok_with([1, 3])
  #   experiment_file.failed_with([1, 4])
  #   experiment_file.build_combinations # => [[4, 5], [1, 3, 4], [1, 3, 5]]
  #   experiment_file.failed_with([1, 3, 4])
  #   experiment_file.build_combinations # => [[4, 5], [1, 3, 5]]
  #   experiment_file.failed_with([4, 5])
  #   experiment_file.build_combinations # => [[1, 3, 5]]
  #   experiment_file.ok_with([1, 3, 5])
  #   experiment_file.build_combinations # => []
  class ExperimentFile
    attr_reader :ok_experiments, :fail_experiments, :experiment

    def initialize(file, experiment)
      @file = file
      @ast = Fast.ast_from_file(file) if file
      @experiment = experiment
      @ok_experiments = []
      @fail_experiments = []
      @round = 0
    end

    # @return [String] from {Fast::Experiment#expression}.
    def search
      experiment.expression
    end

    # @return [String] with a derived name with the combination number.
    def experimental_filename(combination)
      parts = @file.split('/')
      dir = parts[0..-2]
      filename = "experiment_#{[*combination].join('_')}_#{parts[-1]}"
      File.join(*dir, filename)
    end

    # Keep track of ok experiments depending on the current combination.
    # It keep the combinations unique removing single replacements after the
    # first round.
    # @return void
    def ok_with(combination)
      @ok_experiments << combination
      return unless combination.is_a?(Array)

      combination.each do |element|
        @ok_experiments.delete(element)
      end
    end

    # Track failed experiments to avoid run them again.
    # @return [void]
    def failed_with(combination)
      @fail_experiments << combination
    end

    # @return [Array<Astrolabe::Node>]
    def search_cases
      Fast.search(experiment.expression, @ast) || []
    end

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    #
    # Execute partial replacements generating new file with the
    # content replaced.
    # @return [void]
    def partial_replace(*indices)
      replacement = experiment.replacement
      new_content = Fast.replace_file experiment.expression, @file do |node, *captures|
        if indices.nil? || indices.empty? || indices.include?(match_index)
          if replacement.parameters.length == 1
            instance_exec node, &replacement
          else
            instance_exec node, *captures, &replacement
          end
        end
      end
      return unless new_content

      write_experiment_file(indices, new_content)
      new_content
    end

    # rubocop:enable Metrics/AbcSize
    # rubocop:enable Metrics/MethodLength

    # Write new file name depending on the combination
    # @param [Array<Integer>] combination
    # @param [String] new_content to be persisted
    def write_experiment_file(combination, new_content)
      filename = experimental_filename(combination)
      File.open(filename, 'w+') { |f| f.puts new_content }
      filename
    end

    def done!
      count_executed_combinations = @fail_experiments.size + @ok_experiments.size
      puts "Done with #{@file} after #{count_executed_combinations} combinations"
      return unless perfect_combination = @ok_experiments.last # rubocop:disable Lint/AssignmentInCondition

      puts 'The following changes were applied to the file:'
      `diff #{experimental_filename(perfect_combination)} #{@file}`
      puts "mv #{experimental_filename(perfect_combination)} #{@file}"
      `mv #{experimental_filename(perfect_combination)} #{@file}`
    end

    # Increase the `@round` by 1 to {ExperimentCombinations#generate_combinations}.
    def build_combinations
      @round += 1
      ExperimentCombinations.new(
        round: @round,
        occurrences_count: search_cases.size,
        ok_experiments: @ok_experiments,
        fail_experiments: @fail_experiments
      ).generate_combinations
    end

    def run
      while (combinations = build_combinations).any?
        if combinations.size > 1000
          puts "Ignoring #{@file} because it has #{combinations.size} possible combinations"
          break
        end
        puts "#{@file} - Round #{@round} - Possible combinations: #{combinations.inspect}"
        while combination = combinations.shift # rubocop:disable Lint/AssignmentInCondition
          run_partial_replacement_with(combination)
        end
      end
      done!
    end

    # Writes a new file with partial replacements based on the current combination.
    # Raise error if no changes was made with the given combination indices.
    # @param [Array<Integer>] combination to be replaced.
    def run_partial_replacement_with(combination)
      content = partial_replace(*combination)
      experimental_file = experimental_filename(combination)

      File.open(experimental_file, 'w+') { |f| f.puts content }

      raise 'No changes were made to the file.' if FileUtils.compare_file(@file, experimental_file)

      result = experiment.ok_if.call(experimental_file)

      if result
        ok_with(combination)
        puts "✅ #{experimental_file} - Combination: #{combination}"
      else
        failed_with(combination)
        puts "🔴 #{experimental_file} - Combination: #{combination}"
      end
    end
  end
end
