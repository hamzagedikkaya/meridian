require 'rails_helper'

RSpec.describe Subscription, type: :model do
  describe "validations" do
    subject { build(:subscription) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_numericality_of(:amount_cents).is_greater_than(0) }
    it { is_expected.to validate_inclusion_of(:frequency).in_array(described_class::FREQUENCIES) }
  end

  describe "#yearly_amount_cents" do
    it "calculates monthly × 12" do
      sub = build(:subscription, frequency: "monthly", amount_cents: 100_00)
      expect(sub.yearly_amount_cents).to eq(1_200_00)
    end

    it "calculates weekly × 52" do
      sub = build(:subscription, frequency: "weekly", amount_cents: 10_00)
      expect(sub.yearly_amount_cents).to eq(520_00)
    end

    it "returns the amount for yearly" do
      sub = build(:subscription, frequency: "yearly", amount_cents: 999_00)
      expect(sub.yearly_amount_cents).to eq(999_00)
    end
  end

  describe "#advance_next_charge!" do
    it "advances by one month for monthly subs" do
      sub = create(:subscription, frequency: "monthly", next_charge_on: Date.new(2026, 1, 15))
      sub.advance_next_charge!
      expect(sub.next_charge_on).to eq(Date.new(2026, 2, 15))
    end
  end
end
