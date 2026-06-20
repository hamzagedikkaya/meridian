require 'rails_helper'

RSpec.describe "Finance::Budgets", type: :request do
  let(:user) { create(:user) }
  let(:category) { create(:finance_category, user: user, kind: "expense") }

  before { sign_in user }

  describe "GET /finance/budgets" do
    it "renders the index" do
      create(:budget, user: user, finance_category: category)
      get finance_budgets_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include(category.name)
    end

    it "renders the empty state with no budgets" do
      get finance_budgets_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("finance.budgets.none"))
    end
  end

  describe "GET /finance/budgets/new" do
    it "renders the modal form" do
      get new_finance_budget_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /finance/budgets" do
    it "creates a budget, converting the decimal limit to cents by user currency" do
      expect {
        post finance_budgets_path, params: { budget: { finance_category_id: category.id, monthly_limit: "1500" } }
      }.to change(Budget, :count).by(1)
      expect(Budget.last.monthly_limit_cents).to eq(1500_00) # TRY → *100
      expect(response).to redirect_to(finance_budgets_path)
    end

    it "does not multiply by 100 for a GAU (gram-gold) user" do
      user.update!(currency: "GAU")
      post finance_budgets_path, params: { budget: { finance_category_id: category.id, monthly_limit: "5" } }
      expect(Budget.last.monthly_limit_cents).to eq(5)
    end

    it "re-renders with errors on an invalid limit" do
      post finance_budgets_path, params: { budget: { finance_category_id: category.id, monthly_limit: "0" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /finance/budgets/:id" do
    it "updates the limit" do
      budget = create(:budget, user: user, finance_category: category, monthly_limit_cents: 100_00)
      patch finance_budget_path(budget), params: { budget: { monthly_limit: "250" } }
      expect(budget.reload.monthly_limit_cents).to eq(250_00)
    end
  end

  describe "DELETE /finance/budgets/:id" do
    it "removes the budget" do
      budget = create(:budget, user: user, finance_category: category)
      expect { delete finance_budget_path(budget) }.to change(Budget, :count).by(-1)
    end
  end

  describe "per-user scoping" do
    it "cannot touch another user's budget" do
      other = create(:budget)
      expect { delete finance_budget_path(other) }.not_to change(Budget, :count)
      expect(response).to have_http_status(:not_found)
    end
  end
end
