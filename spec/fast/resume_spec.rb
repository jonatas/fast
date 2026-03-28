# frozen_string_literal: true

require 'spec_helper'
require 'fast/resume'

RSpec.describe Fast::Resume do
  describe '#summarize' do
    let(:code) do
      <<~RUBY
        module Store
          class Item < ActiveRecord::Base
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
            
            def self.find_cheap
              2
            end
          end
        end
      RUBY
    end

    subject { described_class.new(code) }

    it 'outputs a comprehensive skeleton' do
      expect { subject.summarize }.to output(<<~EXPECTED).to_stdout
        module Store
          class Item < ActiveRecord::Base
            has_many :variants
            belongs_to :user

            attr_accessor :virtual_price, :*name

            Scopes: active, recent(limit)

            Hooks: before_save :prepare_price, after_create :notify_user

            Validations: *name, :custom_check

            def calculate(tax, extra: 0)
            def self.find_cheap
          end
        end
      EXPECTED
    end
  end
end
