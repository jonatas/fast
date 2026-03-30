# frozen_string_literal: true

require 'spec_helper'
require 'fast/summary'

RSpec.describe Fast::Summary do
  describe '#summarize' do
    let(:code) do
      <<~RUBY
        module Store
          class Item < ActiveRecord::Base
            STATUS = [:draft, :live]

            include Trackable

            has_many :variants
            belongs_to :user

            attr_accessor :virtual_price, :name

            validates :name, presence: true
            validate :custom_check

            before_save :prepare_price
            after_create :notify_user

            scope :active, -> { where(active: true) }
            scope :recent, ->(limit) { order(created_at: :desc).limit(limit) }

            def calculate(tax, extra: 0)
              1
            end

            private

            def hidden_cost
              3
            end

            def self.find_cheap
              2
            end

            class Audit
              def sync
                4
              end
            end
          end
        end
      RUBY
    end

    subject(:summary) { described_class.new(code) }

    it 'outputs a comprehensive skeleton' do
      expect { summary.summarize }.to output(<<~EXPECTED).to_stdout
        module Store
          class Item < ActiveRecord::Base

            STATUS = [...]

            include Trackable

            has_many :variants
            belongs_to :user

            attr_accessor :virtual_price, :name

            Scopes: active, recent(limit)

            Hooks: before_save :prepare_price, after_create :notify_user

            Validations: :name, presence: true, :custom_check

            def calculate(tax, extra: 0)

            private
              def hidden_cost
              def self.find_cheap
            class Audit

              def sync
            end
          end
        end
      EXPECTED
    end

    it 'falls back to Prism for newer Ruby syntax' do
      prism_code = <<~RUBY
        class ModernController
          include Trackable
          before_action :load_user, if: :current_user?

          def analytics(scope)
            payload = {scope:, enabled: true}
          end
        end
      RUBY

      expect { described_class.new(prism_code).summarize }.to output(<<~EXPECTED).to_stdout
        class ModernController

          include Trackable

          Hooks: before_action :load_user, if: :current_user?

          def analytics(scope)
        end
      EXPECTED
    end

    it 'reports unsupported templates clearly' do
      expect { described_class.new('= render :thing', file: 'sample.slim').summarize }
        .to output("Unsupported template format for .summary: .slim\n").to_stdout
    end

    it 'prints large macro sections across multiple lines' do
      code = <<~RUBY
        class DashboardController
          helper_method :current_user
          helper_method :show_sidebar?
          helper_method :show_topbar?
          helper_method :show_notifications?
          helper_method :favorite_reports_manager
        end
      RUBY

      expect { described_class.new(code).summarize }.to output(<<~EXPECTED).to_stdout
        class DashboardController

          Macros:
            helper_method :current_user
            helper_method :show_sidebar?
            helper_method :show_topbar?
            helper_method :show_notifications?
            helper_method :favorite_reports_manager
        end
      EXPECTED
    end

    it 'aggregates top-level requires into a single line' do
      code = <<~RUBY
        require 'json'
        require 'fast'
        require_relative 'helper'

        module Fast
          class McpServer
          end
        end
      RUBY

      expect { described_class.new(code).summarize }.to output(<<~EXPECTED).to_stdout
        requires: "json", "fast", "helper"

        module Fast
          class McpServer
          end
        end
      EXPECTED
    end

    it 'supports level 1 for structural inventory only' do
      expect { described_class.new(code, level: 1).summarize }.to output(<<~EXPECTED).to_stdout
        module Store
          class Item < ActiveRecord::Base
            class Audit
            end
          end
        end
      EXPECTED
    end

    it 'supports level 2 for signals without methods' do
      expect { described_class.new(code, level: 2).summarize }.to output(<<~EXPECTED).to_stdout
        module Store
          class Item < ActiveRecord::Base

            STATUS = [...]

            include Trackable

            has_many :variants
            belongs_to :user

            attr_accessor :virtual_price, :name

            Scopes: active, recent(limit)

            Hooks: before_save :prepare_price, after_create :notify_user

            Validations: :name, presence: true, :custom_check
            class Audit
            end
          end
        end
      EXPECTED
    end
  end
end
