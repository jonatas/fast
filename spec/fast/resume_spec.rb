# frozen_string_literal: true

require 'spec_helper'
require 'fast/resume'

RSpec.describe Fast::Resume do
  describe '#summarize' do
    it 'keeps the legacy command label in unsupported template errors' do
      expect { described_class.new('= render :thing', file: 'sample.slim').summarize }
        .to output("Unsupported template format for .resume: .slim\n").to_stdout
    end

    it 'uses the shared summary behavior' do
      code = <<~RUBY
        class ModernController
          before_action :load_user, if: :current_user?
        end
      RUBY

      expect { described_class.new(code).summarize }.to output(<<~EXPECTED).to_stdout
        class ModernController

          Hooks: before_action :load_user, if: :current_user?
        end
      EXPECTED
    end
  end
end
