require "rails_helper"

RSpec.describe QuickCapture::Amount do
  describe ".parse" do
    {
      "250" => "250",
      "007" => "7",
      "12,50" => "12.50",
      "12.50" => "12.50",
      "12,5" => "12.5",
      "1250,5" => "1250.5",
      "1250.5" => "1250.5",
      "0,250" => "0.25",
      "0.5" => "0.5",
      "1,2500" => "1.25",
      "1250.500" => "1250.5"
    }.each do |input, expected|
      context "with #{input.inspect}, a decimal point" do
        it("reads #{expected}") { expect(described_class.parse(input)).to eq(BigDecimal(expected)) }
      end
    end

    {
      "1.250" => "1250",
      "1,250" => "1250",
      "12.500" => "12500",
      "250.000" => "250000",
      "1.000.000" => "1000000",
      "1,000,000" => "1000000"
    }.each do |input, expected|
      context "with #{input.inspect}, thousands grouping" do
        it("reads #{expected}") { expect(described_class.parse(input)).to eq(BigDecimal(expected)) }
      end
    end

    {
      "1.250,50" => "1250.50",
      "1,250.50" => "1250.50",
      "1.000.000,25" => "1000000.25",
      "1,000,000.25" => "1000000.25"
    }.each do |input, expected|
      context "with #{input.inspect}, both separators (the last one is decimal)" do
        it("reads #{expected}") { expect(described_class.parse(input)).to eq(BigDecimal(expected)) }
      end
    end

    [ "", "abc", "-5", "1 000", ".5", "5.", "1..5", "1.2.3", "12,34,56", "1.25.0", "1,25.5", "1.250,5.5", "1.250,50,1" ].each do |input|
      it "rejects #{input.inspect}" do
        expect(described_class.parse(input)).to be_nil
      end
    end
  end
end
