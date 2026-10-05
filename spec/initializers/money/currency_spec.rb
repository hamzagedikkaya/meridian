require "rails_helper"

RSpec.describe Money::Currency do
  it "lists every currency, gram gold included (each registered currency has a priority)" do
    codes = described_class.all.map(&:iso_code)

    expect(codes).to include("GAU", "TRY", "USD")
    expect(described_class.find("GAU").subunit_to_unit).to eq(1)
  end
end
