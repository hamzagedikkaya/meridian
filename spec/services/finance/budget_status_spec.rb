require 'rails_helper'

RSpec.describe Finance::BudgetStatus do
  let(:user) { create(:user) }
  let(:category) { create(:finance_category, user: user, kind: "expense") }

  def status(spent:, limit: 1_000_00, on: Date.new(2026, 6, 10))
    budget = build(:budget, user: user, finance_category: category, monthly_limit_cents: limit)
    described_class.new(budget: budget, spent_cents: spent, on: on)
  end

  describe "spend math" do
    it "is under budget and on track when spend trails the pace" do
      s = status(spent: 100_00) # 10% used by day 10 of 30
      expect(s.percent_used).to eq(10)
      expect(s.remaining_cents).to eq(900_00)
      expect(s.over?).to be(false)
      expect(s.state).to eq(:under)
      expect(s.on_track?).to be(true)
    end

    it "warns when the run-rate projects an overspend" do
      s = status(spent: 600_00) # 60% used by day 10 → projected 1800 > 1000
      expect(s.will_overspend?).to be(true)
      expect(s.state).to eq(:warning)
      expect(s.over?).to be(false)
    end

    it "flags over budget with the overage" do
      s = status(spent: 1_200_00)
      expect(s.over?).to be(true)
      expect(s.over_by_cents).to eq(200_00)
      expect(s.remaining_cents).to eq(-200_00)
      expect(s.state).to eq(:over)
    end

    it "clamps the bar width but not the percent label" do
      s = status(spent: 1_500_00)
      expect(s.percent_used).to eq(150)
      expect(s.bar_percent).to eq(100)
    end

    it "derives pace from how far into the month it is" do
      expect(status(spent: 0, on: Date.new(2026, 6, 15)).pace_percent).to eq(50) # day 15 of 30
    end
  end

  describe ".for_user / .month_actuals" do
    let(:account) { create(:account, user: user) }

    it "rolls subcategory spend up to the budgeted root category" do
      child = create(:finance_category, user: user, kind: "expense", parent: category)
      create(:transaction, user: user, account: account, finance_category: category, kind: "expense", amount_cents: 200_00, date: Date.current)
      create(:transaction, user: user, account: account, finance_category: child, kind: "expense", amount_cents: 300_00, date: Date.current)
      create(:budget, user: user, finance_category: category, monthly_limit_cents: 1_000_00)

      statuses = described_class.for_user(user)
      expect(statuses.size).to eq(1)
      expect(statuses.first.spent_cents).to eq(500_00) # 200 root + 300 child
    end

    it "ignores income and transactions outside the current month" do
      create(:transaction, user: user, account: account, finance_category: category, kind: "expense", amount_cents: 100_00, date: 2.months.ago)
      create(:budget, user: user, finance_category: category, monthly_limit_cents: 1_000_00)

      expect(described_class.for_user(user).first.spent_cents).to eq(0)
    end
  end
end
