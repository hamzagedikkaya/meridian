require 'rails_helper'

RSpec.describe Budget, type: :model do
  let(:user) { create(:user) }
  let(:expense_root) { create(:finance_category, user: user, kind: "expense") }

  describe "validations" do
    it "requires a positive monthly limit" do
      budget = build(:budget, user: user, finance_category: expense_root, monthly_limit_cents: 0)
      expect(budget).not_to be_valid
      expect(budget.errors[:monthly_limit_cents]).to be_present
    end

    it "allows one budget per category" do
      create(:budget, user: user, finance_category: expense_root)
      dup = build(:budget, user: user, finance_category: expense_root)
      expect(dup).not_to be_valid
      expect(dup.errors[:finance_category_id]).to be_present
    end

    it "rejects an income category" do
      income = create(:finance_category, user: user, kind: "income")
      budget = build(:budget, user: user, finance_category: income)
      expect(budget).not_to be_valid
      expect(budget.errors[:finance_category_id]).to include(I18n.t("activerecord.errors.models.budget.attributes.finance_category_id.must_be_expense"))
    end

    it "rejects a subcategory (must be a root)" do
      child = create(:finance_category, user: user, kind: "expense", parent: expense_root)
      budget = build(:budget, user: user, finance_category: child)
      expect(budget).not_to be_valid
      expect(budget.errors[:finance_category_id]).to include(I18n.t("activerecord.errors.models.budget.attributes.finance_category_id.must_be_root"))
    end
  end

  describe "#monthly_limit money" do
    it "uses the user's currency" do
      user.update!(currency: "USD")
      budget = create(:budget, user: user, finance_category: expense_root, monthly_limit_cents: 1_000_00)
      expect(budget.monthly_limit.currency.iso_code).to eq("USD")
      expect(budget.monthly_limit.to_f).to eq(1000.0)
    end

    it "treats GAU (gram-gold) cents without a 100x assumption" do
      user.update!(currency: "GAU")
      budget = create(:budget, user: user, finance_category: expense_root, monthly_limit_cents: 5)
      # GAU subunit_to_unit is 1, so 5 cents == 5 grams, not 0.05.
      expect(budget.monthly_limit.to_f).to eq(5.0)
    end
  end
end
