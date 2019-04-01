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
    #  Fast.experiment("RSpec/RemoveUselessBeforeAfterHook") do
    #    lookup 'spec'
    #    search "(block (send nil {before after}))"
    #    edit { |node| remove(node.loc.expression) }
    #    policy { |new_file| system("rspec --fail-fast #{new_file}") }
    #  end
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
  # @example
  #  Fast.experiment("RSpec/RemoveUselessBeforeAfterHook") do
  #    lookup 'some_spec.rb'
  #    search "(block (send nil {before after}))"
  #    edit {|node| remove(node.loc.expression) }
  #    policy {|new_file| system("bin/spring rspec --fail-fast #{new_file}") }
  #  end
  #
  # ## Example 2: use build_stubbed instead of create
  #
  # Let's say you want to try to automate some replacement of
  # `FactoryBot.create` to use `FactoryBot.build_stubbed`.
  #
  # For specs let's consider the example we want to refactor:
  #
  # @code
  #  let(:person) { create(:person, :with_email) }
  #
  # And the intent is refactor to use `build_stubbed` instead of `replace`:
  #
  # @code
  #  let(:person) { build_stubbed(:person, :with_email) }
  #
  # Here is the experiment definition:
  #
  # @example
  #  Fast.experiment('RSpec/ReplaceCreateWithBuildStubbed') do
  #    lookup 'spec'
  #    search '(block (send nil let (sym _)) (args) $(send nil create))'
  #    edit { |_, (create)| replace(create.loc.selector, 'build_stubbed') }
  #    policy { |new_file| system("bin/spring rspec --format progress --fail-fast #{new_file}") }
  #  end
  class Experiment
    attr_writer :files
    attr_reader :name, :replacement, :expression, :files_or_folders, :ok_if

    def initialize(name, &block)
      @name = name
      puts "\nStarting experiment: #{name}"
      instance_exec(&block)
    end

    def run_with(file)
      ExperimentFile.new(file, self).run
    end

    def search(expression)
      @expression = expression
    end

    def edit(&block)
      @replacement = block
    end

    def lookup(files_or_folders)
      @files_or_folders = files_or_folders
    end

    def policy(&block)
      @ok_if = block
    end

    def files
      @files ||= Fast.ruby_files_from(@files_or_folders)
    end

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

    # Combining all successful individual replacements has failed. Lets divide
    # and conquer.
    def ok_replacements_pair_combinations
      @ok_experiments
        .combination(2)
        .map { |e| e.flatten.uniq.sort }
        .uniq - @fail_experiments - @ok_experiments
    end
  end

  # Encapsulate the join of an Experiment with an specific file.
  # This is important to coordinate and regulate multiple experiments in the same file.
  # It can track successfull experiments and failures and suggest new combinations to keep replacing the file.
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

    def search
      experiment.expression
    end

    def experimental_filename(combination)
      parts = @file.split('/')
      dir = parts[0..-2]
      filename = "experiment_#{[*combination].join('_')}_#{parts[-1]}"
      File.join(*dir, filename)
    end

    def ok_with(combination)
      @ok_experiments << combination
      return unless combination.is_a?(Array)

      combination.each do |element|
        @ok_experiments.delete(element)
      end
    end

    def failed_with(combination)
      @fail_experiments << combination
    end

    def search_cases
      Fast.search(@ast, experiment.expression) || []
    end

    # rubocop:disable Metrics/AbcSize
    # rubocop:disable Metrics/MethodLength
    def partial_replace(*indices)
      replacement = experiment.replacement
      new_content = Fast.replace_file @file, experiment.expression do |node, *captures|
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

    def write_experiment_file(index, new_content)
      filename = experimental_filename(index)
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

    def run_partial_replacement_with(combination) # rubocop:disable Metrics/AbcSize
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
