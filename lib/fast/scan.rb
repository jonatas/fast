# frozen_string_literal: true

module Fast
  class Scan
    GROUPS = {
      models: 'Models',
      controllers: 'Controllers',
      services: 'Services',
      jobs: 'Jobs',
      mailers: 'Mailers',
      libraries: 'Libraries',
      other: 'Other'
    }.freeze

    MAX_METHODS = 5
    MAX_SIGNALS = 4
    MAX_MACROS = 3

    def initialize(locations, command_name: '.scan')
      @locations = Array(locations)
      @command_name = command_name
    end

    def scan
      files = Fast.ruby_files_from(*@locations)
      grouped = files.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |file, memo|
        entries = Fast.summary(IO.read(file), file: file, command_name: @command_name).outline
        next if entries.empty?

        memo[classify(file, entries)] << [file, entries]
      end

      print_grouped(grouped)
    end

    private

    def classify(file, entries)
      entries = structural_entries(entries)

      return :models if file.include?('/models/') || model_like?(entries)
      return :controllers if file.include?('/controllers/') || controller_like?(entries)
      return :services if file.include?('/services/') || name_like?(entries, /Service\z/)
      return :jobs if file.include?('/jobs/') || name_like?(entries, /Job\z/)
      return :mailers if file.include?('/mailers/') || name_like?(entries, /Mailer\z/)
      return :libraries if file.start_with?('lib/')

      :other
    end

    def model_like?(entries)
      entries.any? do |entry|
        superclass = entry[:superclass].to_s
        superclass.end_with?('ApplicationRecord', 'ActiveRecord::Base') ||
          entry[:relationships].any? ||
          entry[:validations].any? ||
          entry[:scopes].any?
      end
    end

    def controller_like?(entries)
      entries.any? do |entry|
        superclass = entry[:superclass].to_s
        superclass.end_with?('Controller', 'BaseController', 'ApplicationController') ||
          entry[:hooks].any? { |hook| hook.include?('_action') }
      end
    end

    def name_like?(entries, pattern)
      entries.any? { |entry| entry[:name].to_s.match?(pattern) }
    end

    def print_grouped(grouped)
      GROUPS.each do |key, label|
        files = grouped[key]
        next if files.empty?

        puts "#{label}:"
        files.sort_by(&:first).each do |file, entries|
          print_file(file, entries)
        end
        puts
      end
    end

    def print_file(file, entries)
      entries = structural_entries(entries)
      return if entries.empty?

      puts "- #{file}"
      entries.each do |entry|
        puts "  #{entry[:headline]}"

        signals = build_signals(entry)
        puts "  signals: #{signals.join(' | ')}" if signals.any?

        methods = build_methods(entry)
        puts "  methods: #{methods.join(', ')}" if methods.any?

        puts "  nested: #{entry[:nested].join(', ')}" if entry[:nested].any?
      end
    end

    def structural_entries(entries)
      filtered = entries.select { |entry| %i[module class].include?(entry[:kind]) }
      filtered.empty? ? entries.reject { |entry| entry[:kind] == :send } : filtered
    end

    def build_signals(entry)
      signals = []
      signals << summarize_section('relationships', entry[:relationships]) if entry[:relationships].any?
      signals << summarize_section('hooks', entry[:hooks]) if entry[:hooks].any?
      signals << summarize_section('validations', entry[:validations]) if entry[:validations].any?
      signals << summarize_section('scopes', entry[:scopes]) if entry[:scopes].any?
      signals << summarize_section('macros', entry[:macros], limit: MAX_MACROS) if entry[:macros].any?
      signals << summarize_section('mixins', entry[:mixins]) if entry[:mixins].any?
      signals.first(MAX_SIGNALS)
    end

    def summarize_section(name, values, limit: 2)
      preview = values.first(limit).join(', ')
      suffix = values.length > limit ? ", +#{values.length - limit}" : ''
      "#{name}=#{preview}#{suffix}"
    end

    def build_methods(entry)
      public_methods = entry[:methods][:public].first(MAX_METHODS)
      private_methods = entry[:methods][:private].first(2)

      methods = public_methods.dup
      methods << "private: #{private_methods.join(', ')}" if private_methods.any?
      methods
    end
  end
end
