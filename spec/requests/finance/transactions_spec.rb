require 'rails_helper'

RSpec.describe "Finance::Transactions", type: :request do
  let(:user) { create(:user) }
  let(:account) { create(:account, user: user) }
  let(:category) { create(:finance_category, user: user, kind: "expense") }

  before { sign_in user }

  describe "GET /finance/transactions" do
    it "renders" do
      get finance_transactions_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /finance/transactions" do
    it "creates a transaction and redirects" do
      params = { transaction: { account_id: account.id, finance_category_id: category.id, amount: "42.50", kind: "expense", description: "Coffee", date: Date.current } }
      expect { post finance_transactions_path, params: params }
        .to change(Transaction, :count).by(1)
      expect(response).to redirect_to(finance_transactions_path)
    end
  end

  describe "GET /finance/export.csv" do
    it "returns CSV content" do
      create(:transaction, user: user, account: account, finance_category: category, description: "Snack")
      get finance_transactions_export_path(format: :csv)
      expect(response).to have_http_status(:success)
      expect(response.content_type).to start_with("text/csv")
      expect(response.body).to include("Snack")
    end
  end
end
