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

    it "shows income, expense and net totals for the filtered set" do
      create(:transaction, :income, user: user, amount_cents: 100_000)
      create(:transaction, user: user, amount_cents: 30_000) # expense

      get finance_transactions_path

      helpers = ApplicationController.helpers
      expect(response.body).to include(I18n.t("finance.transactions.net"))
      # net = 70_000 only appears in the summary strip, proving it was computed
      # over the whole filtered set rather than a single row.
      expect(response.body).to include(helpers.money_format(70_000, currency: user.currency))
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

    it "filters by account_id, hiding transactions on other accounts" do
      other_account = create(:account, user: user, name: "Savings")

      mine    = create(:transaction, user: user, account: account,       finance_category: category, description: "OnThisAccount", kind: "expense")
      theirs  = create(:transaction, user: user, account: other_account, finance_category: category, description: "OnOtherAccount", kind: "expense")

      get finance_transactions_path, params: { account_id: account.id }
      expect(response.body).to include(mine.description)
      expect(response.body).not_to include(theirs.description)
    end

    it "combines a category_id and an account_id filter (AND semantics)" do
      other_account = create(:account, user: user, name: "Savings")
      food = create(:finance_category, user: user, kind: "expense", name: "Food")

      match       = create(:transaction, user: user, account: account,       finance_category: food,     description: "MatchBoth", kind: "expense")
      wrong_acct  = create(:transaction, user: user, account: other_account, finance_category: food,     description: "WrongAccount", kind: "expense")
      wrong_cat   = create(:transaction, user: user, account: account,       finance_category: category, description: "WrongCategory", kind: "expense")

      get finance_transactions_path, params: { account_id: account.id, category_id: food.id }
      expect(response.body).to include(match.description)
      expect(response.body).not_to include(wrong_acct.description)
      expect(response.body).not_to include(wrong_cat.description)
    end

    it "filters by kind" do
      income_cat = create(:finance_category, user: user, kind: "income", name: "Salary")
      income  = create(:transaction, :income, user: user, account: account, finance_category: income_cat, description: "Paycheck")
      expense = create(:transaction, user: user, account: account, finance_category: category, description: "Groceries", kind: "expense")

      get finance_transactions_path, params: { kind: "income" }
      expect(response.body).to include(income.description)
      expect(response.body).not_to include(expense.description)
    end
  end

  describe "GET /finance/transactions/new" do
    it "renders the new form" do
      get new_finance_transaction_path
      expect(response).to have_http_status(:success)
    end

    it "seeds the kind from the :kind param" do
      get new_finance_transaction_path, params: { kind: "income" }
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /finance/transactions/:id" do
    it "shows the transaction" do
      tx = create(:transaction, user: user, account: account, finance_category: category, description: "ShownTx")
      get finance_transaction_path(tx)
      expect(response).to have_http_status(:success)
      expect(response.body).to include("ShownTx")
    end
  end

  describe "GET /finance/transactions/:id/edit" do
    it "renders the edit form" do
      tx = create(:transaction, user: user, account: account, finance_category: category, description: "EditMe")
      get edit_finance_transaction_path(tx)
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

    it "re-renders :new with 422 when the transaction is invalid" do
      # amount_cents must be > 0; a blank amount leaves it nil/zero → invalid.
      params = { transaction: { account_id: account.id, finance_category_id: category.id, amount: "", kind: "expense", description: "Bad", date: Date.current } }
      expect { post finance_transactions_path, params: params }.not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    context "when the linked block is enabled" do
      let(:dest) { create(:account, user: user, name: "Wallet") }
      let(:linked_params) do
        { transaction: {
          account_id: account.id, finance_category_id: category.id,
          amount: "100", kind: "expense", description: "Linked spend", date: Date.current,
          linked: { enabled: "1", account_id: dest.id, amount: "100" }
        } }
      end

      it "creates both the primary and counterpart transactions and redirects" do
        expect { post finance_transactions_path, params: linked_params }
          .to change(Transaction, :count).by(2)
        expect(response).to redirect_to(finance_transactions_path)
      end

      it "flips the kind and targets the destination account on the counterpart" do
        post finance_transactions_path, params: linked_params
        primary = Transaction.find_by(description: "Linked spend", account_id: account.id)
        linked  = Transaction.where(parent_transaction_id: primary.id).first
        expect(linked.kind).to eq("income")          # flipped from the primary expense
        expect(linked.account_id).to eq(dest.id)
        expect(linked.amount_cents).to eq(100_00)    # 100 * 100 subunits for fiat
      end
    end

    it "ignores the linked block when its required fields are blank" do
      params = {
        transaction: {
          account_id: account.id, finance_category_id: category.id,
          amount: "20", kind: "expense", description: "Solo", date: Date.current,
          linked: { enabled: "1", account_id: "", amount: "" }
        }
      }
      expect { post finance_transactions_path, params: params }
        .to change(Transaction, :count).by(1)
      expect(response).to redirect_to(finance_transactions_path)
    end

    it "rolls back both rows and re-renders :new when the linked counterpart is invalid" do
      # A linked amount of 0 produces amount_cents 0, which fails the > 0 validation
      # on the counterpart only, exercising the rescue/rollback branch.
      dest = create(:account, user: user, name: "Wallet")
      params = {
        transaction: {
          account_id: account.id, finance_category_id: category.id,
          amount: "30", kind: "expense", description: "RollbackMe", date: Date.current,
          linked: { enabled: "1", account_id: dest.id, amount: "0" }
        }
      }
      expect { post finance_transactions_path, params: params }.not_to change(Transaction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /finance/transactions/:id" do
    it "updates the transaction and redirects" do
      tx = create(:transaction, user: user, account: account, finance_category: category, description: "Old")
      patch finance_transaction_path(tx), params: { transaction: { description: "New", amount_cents: tx.amount_cents } }
      expect(response).to redirect_to(finance_transactions_path)
      expect(tx.reload.description).to eq("New")
    end

    it "re-renders :edit with 422 when the update is invalid" do
      tx = create(:transaction, user: user, account: account, finance_category: category, description: "Keep")
      patch finance_transaction_path(tx), params: { transaction: { amount_cents: 0 } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(tx.reload.description).to eq("Keep")
    end
  end

  describe "DELETE /finance/transactions/:id" do
    it "destroys the transaction and redirects" do
      tx = create(:transaction, user: user, account: account, finance_category: category)
      expect { delete finance_transaction_path(tx) }.to change(Transaction, :count).by(-1)
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
