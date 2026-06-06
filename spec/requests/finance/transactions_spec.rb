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

    it "expands a root category filter to include its subcategories" do
      root = create(:finance_category, user: user, kind: "expense", name: "Market")
      child = create(:finance_category, user: user, kind: "expense", name: "Abur Cubur", parent: root)
      other = create(:finance_category, user: user, kind: "expense", name: "Eğlence")

      tx_root  = create(:transaction, user: user, account: account, finance_category: root,  description: "Pazar", kind: "expense")
      tx_child = create(:transaction, user: user, account: account, finance_category: child, description: "Çikolata", kind: "expense")
      tx_other = create(:transaction, user: user, account: account, finance_category: other, description: "Sinema", kind: "expense")

      get finance_transactions_path, params: { category_id: root.id }
      expect(response.body).to include(tx_root.description)
      expect(response.body).to include(tx_child.description)
      expect(response.body).not_to include(tx_other.description)
    end

    it "treats a subcategory filter as an exact match (no parent leak)" do
      root  = create(:finance_category, user: user, kind: "expense", name: "Market")
      child = create(:finance_category, user: user, kind: "expense", name: "Abur Cubur", parent: root)

      tx_root  = create(:transaction, user: user, account: account, finance_category: root,  description: "Pazar", kind: "expense")
      tx_child = create(:transaction, user: user, account: account, finance_category: child, description: "Çikolata", kind: "expense")

      get finance_transactions_path, params: { category_id: child.id }
      expect(response.body).to include(tx_child.description)
      expect(response.body).not_to include(tx_root.description)
    end
  end

  describe "POST /finance/transactions" do
    it "creates a transaction and redirects" do
      params = { transaction: { account_id: account.id, finance_category_id: category.id, amount: "42.50", kind: "expense", description: "Coffee", date: Date.current } }
      expect { post finance_transactions_path, params: params }
        .to change(Transaction, :count).by(1)
      expect(response).to redirect_to(finance_transactions_path)
    end

    it "scales :amount by the account currency's subunit ratio (5 gram of gold stays 5, not 500)" do
      gold_account = create(:account, user: user, currency: "GAU")
      params = { transaction: { account_id: gold_account.id, amount: "5", kind: "income", description: "Bonus", date: Date.current } }
      expect { post finance_transactions_path, params: params }.to change(Transaction, :count).by(1)
      expect(Transaction.last.amount_cents).to eq(5)
    end

    it "still uses 100x for fiat accounts (42.50 TRY → 4250 cents)" do
      params = { transaction: { account_id: account.id, amount: "42.50", kind: "expense", description: "Coffee", date: Date.current } }
      post finance_transactions_path, params: params
      expect(Transaction.last.amount_cents).to eq(4250)
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
