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

    it "goes back to the start date's day after a short month instead of keeping the 28th" do
      sub = create(:subscription, frequency: "monthly", start_date: Date.new(2027, 1, 31), next_charge_on: Date.new(2027, 1, 31))

      dates = Array.new(4) { sub.advance_next_charge! && sub.next_charge_on }

      expect(dates).to eq([ Date.new(2027, 2, 28), Date.new(2027, 3, 31), Date.new(2027, 4, 30), Date.new(2027, 5, 31) ])
    end

    it "keeps 29 February for a yearly subscription that started on it, in leap years" do
      sub = create(:subscription, frequency: "yearly", start_date: Date.new(2028, 2, 29), next_charge_on: Date.new(2029, 2, 28))

      dates = Array.new(3) { sub.advance_next_charge! && sub.next_charge_on }

      expect(dates).to eq([ Date.new(2030, 2, 28), Date.new(2031, 2, 28), Date.new(2032, 2, 29) ])
    end

    it "keeps a next charge date the user moved to another day" do
      sub = create(:subscription, frequency: "monthly", start_date: Date.new(2027, 1, 31), next_charge_on: Date.new(2027, 3, 15))

      sub.advance_next_charge!

      expect(sub.next_charge_on).to eq(Date.new(2027, 4, 15))
    end
  end

  describe "#monthly_amount_cents" do
    it "is the amount for monthly subscriptions and a twelfth of the yearly amount, rounded down, otherwise" do
      expect(build(:subscription, frequency: "monthly", amount_cents: 99_99).monthly_amount_cents).to eq(99_99)
      expect(build(:subscription, frequency: "weekly", amount_cents: 10_00).monthly_amount_cents).to eq(43_33)
      expect(build(:subscription, frequency: "yearly", amount_cents: 1_000_00).monthly_amount_cents).to eq(83_33)
    end
  end
end
