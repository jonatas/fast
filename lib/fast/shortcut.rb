# frozen_string_literal: true

# Allow user to define shortcuts and reuse them in the command line.
module Fast
  class << self
    # Where to search for `Fastfile` archives?
    # 1. Current directory that the command is being runned
    # 2. Home folder
    # 3. Using the `FAST_FILE_DIR` variable to set an extra folder
    LOOKUP_FAST_FILES_DIRECTORIES = [
      Dir.pwd,
      ENV['HOME'],
      ENV['FAST_FILE_DIR'],
      File.join(File.dirname(__FILE__), '..', '..')
    ].reverse.compact.map(&File.method(:expand_path)).uniq.freeze

    # Store predefined searches with default paths through shortcuts.
    # define your Fastfile in you root folder or
    # @example Shortcut for finding validations in rails models
    #   Fast.shortcut(:validations, "(send nil {validate validates})", "app/models")
    def shortcut(identifier, *args, &block)
      shortcuts[identifier] = Shortcut.new(*args, &block)
    end

    # Stores shortcuts in a simple hash where the key is the identifier
    # and the value is the object itself.
    # @return [Hash<String,Shortcut>] as a dictionary.
    def shortcuts
      @shortcuts ||= {}
    end

    # @return [Array<String>] with existent Fastfiles from {LOOKUP_FAST_FILES_DIRECTORIES}.
    def fast_files
      @fast_files ||= LOOKUP_FAST_FILES_DIRECTORIES.compact
        .map { |dir| File.join(dir, 'Fastfile') }
        .select(&File.method(:exist?))
    end

    # Loads `Fastfiles` from {.fast_files} list
    def load_fast_files!
      fast_files.each(&method(:load))
    end
  end

  # Wraps shortcuts for repeated command line actions or build custom scripts
  # with shorcut blocks
  # This is an utility that can be used preloading several shortcuts
  # The shortcut structure will be consumed by [Fast::Cli] and feed with the
  # command line arguments in realtime.
  class Shortcut
    attr_reader :args
    def initialize(*args, &block)
      @args = args if args.any?
      @block = block
    end

    def single_run_with_block?
      @block && @args.nil?
    end

    # Merge extra arguments from input returning a new arguments array keeping
    # the options from previous alias and replacing the files with the
    # @param [Array] extra_args
    def merge_args(extra_args)
      all_args = (@args + extra_args).uniq
      options = all_args.select { |arg| arg.start_with? '-' }
      files = extra_args.select(&File.method(:exist?))
      command = (@args - options - files).first

      [command, *options, *files]
    end

    # If the shortcut was defined with a single block and no extra arguments, it
    # only runs the block and return the result of the yielded block.
    # The block is also executed in the [Fast] module level. Making it easy to
    # implement smalls scripts using several Fast methods.
    # Use ARGV to catch regular arguments from command line if the block is
    # given.
    #
    # @return [Hash<String, Array<Astrolabe::Node>] with file => search results.
    def run
      Fast.instance_exec(&@block) if single_run_with_block?
    end
  end
end
