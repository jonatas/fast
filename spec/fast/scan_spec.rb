# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fast/scan'

RSpec.describe Fast::Scan do
  let(:root) { Dir.mktmpdir('fast-scan') }

  before do
    FileUtils.mkdir_p(File.join(root, 'app/models'))
    FileUtils.mkdir_p(File.join(root, 'app/controllers'))
    FileUtils.mkdir_p(File.join(root, 'app/services'))

    File.write(File.join(root, 'app/models/order.rb'), <<~RUBY)
      class Order < ApplicationRecord
        belongs_to :customer
        has_many :line_items
        validates :reference, presence: true
        before_save :normalize_reference

        def submit!
        end

        private

        def normalize_reference
        end
      end
    RUBY

    File.write(File.join(root, 'app/controllers/orders_controller.rb'), <<~RUBY)
      class OrdersController < ApplicationController
        before_action :load_order

        def update
        end

        private

        def load_order
        end
      end
    RUBY

    File.write(File.join(root, 'app/services/invoice_sync_service.rb'), <<~RUBY)
      module Billing
        class InvoiceSyncService
          def call
          end

          private

          def push_invoice
          end
        end
      end
    RUBY
  end

  after do
    FileUtils.remove_entry(root)
  end

  it 'groups files by category and prints bounded summaries' do
    scan = described_class.new([
      File.join(root, 'app/models'),
      File.join(root, 'app/controllers'),
      File.join(root, 'app/services')
    ])

    expect { scan.scan }.to output(<<~OUT).to_stdout
      Models:
      - #{File.join(root, 'app/models/order.rb')}
        Order < ApplicationRecord
        signals: relationships=belongs_to :customer, has_many :line_items | hooks=before_save :normalize_reference | validations=:reference, presence: true
        methods: Order#submit!, private Order#normalize_reference

      Controllers:
      - #{File.join(root, 'app/controllers/orders_controller.rb')}
        OrdersController < ApplicationController
        signals: hooks=before_action :load_order
        methods: OrdersController#update, private OrdersController#load_order

      Services:
      - #{File.join(root, 'app/services/invoice_sync_service.rb')}
        Billing::InvoiceSyncService
        methods: Billing::InvoiceSyncService#call, private Billing::InvoiceSyncService#push_invoice

    OUT
  end

  it 'supports lower detail levels for repo triage' do
    scan = described_class.new([
      File.join(root, 'app/models'),
      File.join(root, 'app/controllers'),
      File.join(root, 'app/services')
    ], level: 1)

    expect { scan.scan }.to output(<<~OUT).to_stdout
      Models:
      - #{File.join(root, 'app/models/order.rb')}
        Order < ApplicationRecord

      Controllers:
      - #{File.join(root, 'app/controllers/orders_controller.rb')}
        OrdersController < ApplicationController

      Services:
      - #{File.join(root, 'app/services/invoice_sync_service.rb')}
        Billing::InvoiceSyncService

    OUT
  end

  it 'shows signals but omits methods at level 2' do
    scan = described_class.new([
      File.join(root, 'app/models')
    ], level: 2)

    expect { scan.scan }.to output(<<~OUT).to_stdout
      Models:
      - #{File.join(root, 'app/models/order.rb')}
        Order < ApplicationRecord
        signals: relationships=belongs_to :customer, has_many :line_items | hooks=before_save :normalize_reference | validations=:reference, presence: true

    OUT
  end
end
