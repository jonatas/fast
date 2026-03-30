require 'rspec'
require 'ostruct'

# Mocking necessary methods to make tests pass standalone
module DummyHelpers
  def create(sym)
    OpenStruct.new(name: 'Legacy')
  end
  def build_stubbed(sym)
    OpenStruct.new(name: 'Legacy')
  end
end

RSpec.configure do |c|
  c.include DummyHelpers
end

RSpec.describe 'Dummy API' do
  let!(:user) { create(:user) }
  let(:address) { create(:address) }

  before do
    @useless = true
  end

  after do
    @useless = false
  end

  it 'does something' do
    user = create(:user)
    def user.update_attributes(hash)
      self.name = hash[:name]
    end
    def user.update(hash)
      self.name = hash[:name]
    end

    expect(File.exist?(__FILE__)).to eq(true)
    user.update_attributes(name: 'Jonatas')
    expect(user.name).to eq('Jonatas')
  end
end
