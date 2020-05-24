# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Fast do
  let(:sample_ruby_class) do
    <<~RUBY
      # One new comment
      class SelfPromotion
        AUTHOR = "Jônatas Davi Paganini"
        def initialize(name, language='pt')
          @name = name
          @lang = language if LANGUAGES.include?(language)
        end
        def welcome
          case @lang
          when 'pt' then puts "Olá \#{@name}"
          when 'es' then puts "Hola \#{@name}"
          else puts "Hello \#{@name}"
          end
        end
        def self.thanks
          welcome_message = new('friend', 'en')
          message = [AUTHOR, "wants to say", welcome_message]
          puts message.join(' ')
        end
      end
    RUBY
  end

  describe described_class::Rewriter do
    let(:rename_variable_rewriter) do
      rewriter = described_class.new
      rewriter.ast = Fast.ast('a = 1')
      rewriter.search = '(lvasgn _ ...)'
      rewriter.replacement = ->(node) { replace(node.location.name, 'variable_renamed') }
      rewriter
    end

    describe '#rewrite!' do
      it 'runs replacement block' do
        expect(rename_variable_rewriter.rewrite!).to eq('variable_renamed = 1')
      end
    end
  end

  describe '.replace_file' do
    before { File.open('sample.rb', 'w+') { |file| file.puts sample_ruby_class } }

    after { File.delete('sample.rb') }

    context 'with rename constant example' do
      let(:rename_const) do
        described_class.replace_file('{(const nil? :AUTHOR) (casgn nil? :AUTHOR ...)}', 'sample.rb') do |node|
          target = node.const_type? ? node.loc.expression : node.loc.name
          replace(target, 'CREATOR')
        end
      end

      it 'replaces all occurrences' do # rubocop:disable RSpec/ExampleLength
        expect(rename_const).to eq(<<~RUBY)
          # One new comment
          class SelfPromotion
            CREATOR = "Jônatas Davi Paganini"
            def initialize(name, language='pt')
              @name = name
              @lang = language if LANGUAGES.include?(language)
            end
            def welcome
              case @lang
              when 'pt' then puts "Olá \#{@name}"
              when 'es' then puts "Hola \#{@name}"
              else puts "Hello \#{@name}"
              end
            end
            def self.thanks
              welcome_message = new('friend', 'en')
              message = [CREATOR, "wants to say", welcome_message]
              puts message.join(' ')
            end
          end
        RUBY
      end
    end

    context 'when inline local variable example' do
      let(:inline_var) do
        described_class.replace_file('{(lvasgn :message _) (lvar :message)}', 'sample.rb') do |node|
          if node.lvasgn_type?
            @assignment = node.children.last
            remove(node.loc.expression)
          else
            replace(node.loc.expression,
                    @assignment.source) # rubocop:disable RSpec/InstanceVariable
          end
        end
      end

      it 'replaces all occurrences' do
        expect(inline_var).to eq(<<~RUBY)
          # One new comment
          class SelfPromotion
            AUTHOR = "Jônatas Davi Paganini"
            def initialize(name, language='pt')
              @name = name
              @lang = language if LANGUAGES.include?(language)
            end
            def welcome
              case @lang
              when 'pt' then puts "Olá \#{@name}"
              when 'es' then puts "Hola \#{@name}"
              else puts "Hello \#{@name}"
              end
            end
            def self.thanks
              welcome_message = new('friend', 'en')\n\s\s\s\s
              puts [AUTHOR, "wants to say", welcome_message].join(' ')
            end
          end
        RUBY
      end
    end
  end

  describe '.replace' do
    subject { described_class.replace(expression, example, &replacement) }

    context 'with a local variable rename' do
      let(:example) { Fast.ast('a = 1') }
      let(:expression) { '(lvasgn _ ...)' }
      let(:replacement) { ->(node) { replace(node.location.name, 'variable_renamed') } }

      it { is_expected.to eq 'variable_renamed = 1' }
    end

    context 'with the method with a `delegate` call' do
      let(:example) { Fast.ast 'def name; person.name end' }
      let(:expression) { '(def $_ (_) (send (send nil? $_) _))' }
      let(:replacement) do
        lambda do |node, captures|
          new_source = "delegate :#{captures[0]}, to: :#{captures[1]}"
          replace(node.location.expression, new_source)
        end
      end

      it { is_expected.to eq('delegate :name, to: :person') }
    end

    context 'when call !a.empty?` with `a.any?`' do
      let(:example) { Fast.ast '!a.empty?' }
      let(:expression) { '(send (send (send nil? $_ ) :empty?) :!)' }
      let(:replacement) { ->(node, captures) { replace(node.location.expression, "#{captures[0]}.any?") } }

      it { is_expected.to eq('a.any?') }
    end

    context 'when use `match_index` to filter an specific occurence' do
      let(:example) { Fast.ast 'create(:a, :b, :c);create(:b, :c, :d)' }
      let(:expression) { '(send nil? :create ...)' }
      let(:replacement) { ->(node, _captures) { replace(node.location.selector, 'build_stubbed') if match_index == 2 } }

      it { is_expected.to eq('create(:a, :b, :c);build_stubbed(:b, :c, :d)') }
    end
  end

  describe '.rewrite_file' do
    subject(:remove_methods) do
      Fast.rewrite_file('{def defs}', 'sample.rb') do |node, _|
        remove(node.location.expression)
      end
    end

    before { File.open('sample.rb', 'w+') { |file| file.puts sample_ruby_class } }

    after { File.delete('sample.rb') }

    specify do
      expect { remove_methods }.to change { IO.read('sample.rb') }.to(<<~RUBY)
        # One new comment
        class SelfPromotion
          AUTHOR = "Jônatas Davi Paganini"
        \s\s
        \s\s
        \s\s
        end
      RUBY
    end
  end
end
