require "rails_helper"

RSpec.describe "Api::V1::Transactions", type: :request do
  let(:user) { create(:user) }
  let(:auth) { { "Authorization" => "Bearer #{user.api_token}" } }
  let(:account) { create(:account, user: user, name: "Wallet") }
  let(:category) { create(:finance_category, user: user, name: "Market") }

  it "returns JSON 401 without a token" do
    get api_v1_transactions_path

    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)["error"]).to eq("unauthorized")
  end

  describe "GET /api/v1/transactions" do
    it "lists only the current user's transactions, recent first, with exact fields and meta" do
      expense = create(:transaction, user: user, account: account, finance_category: category,
                       amount_cents: 250_00, date: Date.current, description: "Groceries", note: "weekly")
      create(:transaction, :income, user: user, account: account, amount_cents: 1_000_00, date: Date.current - 1)
      create(:transaction, :transfer, user: user, account: account, amount_cents: 300_00, date: Date.current - 2)
      create(:transaction, description: "Someone else's")

      get api_v1_transactions_path, headers: auth

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["transactions"].size).to eq(3)
      expect(body["transactions"].first).to eq(
        "id" => expense.id,
        "kind" => "expense",
        "amount_cents" => 25_000,
        "date" => Date.current.iso8601,
        "description" => "Groceries",
        "note" => "weekly",
        "account" => {
          "id" => account.id, "name" => "Wallet", "color" => "#B8860B",
          "currency" => "TRY", "subunit_to_unit" => 100
        },
        "category" => {
          "id" => category.id, "name" => "Market", "kind" => "expense",
          "color" => "#A09B8E", "parent_id" => nil, "position" => 0
        },
        "related_account" => nil
      )
      expect(body["meta"]).to eq(
        "total_count" => 3,
        "page" => 1,
        "page_limit" => 50,
        "filtered_income_cents" => 100_000,
        "filtered_expense_cents" => 25_000
      )
    end

    it "filters by kind, account and date range" do
      other_account = create(:account, user: user)
      old = create(:transaction, user: user, account: account, date: 40.days.ago.to_date)
      recent_expense = create(:transaction, user: user, account: account, date: Date.current)
      income = create(:transaction, :income, user: user, account: other_account, date: Date.current)

      get api_v1_transactions_path, params: { kind: "income" }, headers: auth
      expect(JSON.parse(response.body)["transactions"].map { |t| t["id"] }).to eq([ income.id ])

      get api_v1_transactions_path, params: { account_id: account.id }, headers: auth
      expect(JSON.parse(response.body)["transactions"].map { |t| t["id"] }).to eq([ recent_expense.id, old.id ])

      get api_v1_transactions_path, params: { from: 7.days.ago.to_date.iso8601, to: Date.current.iso8601 }, headers: auth
      expect(JSON.parse(response.body)["transactions"].map { |t| t["id"] }).to contain_exactly(recent_expense.id, income.id)
    end

    it "expands a root category filter to its children while a child stays exact" do
      child = create(:finance_category, user: user, name: "Atıştırmalık", parent: category)
      in_child = create(:transaction, user: user, account: account, finance_category: child)
      in_root = create(:transaction, user: user, account: account, finance_category: category)
      create(:transaction, user: user, account: account)

      get api_v1_transactions_path, params: { category_id: category.id }, headers: auth
      expect(JSON.parse(response.body)["transactions"].map { |t| t["id"] }).to contain_exactly(in_child.id, in_root.id)

      get api_v1_transactions_path, params: { category_id: child.id }, headers: auth
      expect(JSON.parse(response.body)["transactions"].map { |t| t["id"] }).to eq([ in_child.id ])
    end

    it "paginates with a limit of 50 per page" do
      old = create(:transaction, user: user, account: account, finance_category: category, date: 2.years.ago.to_date)
      50.times { create(:transaction, user: user, account: account, finance_category: category, date: Date.current) }

      get api_v1_transactions_path, headers: auth
      body = JSON.parse(response.body)
      expect(body["transactions"].size).to eq(50)
      expect(body["transactions"].map { |t| t["id"] }).not_to include(old.id)

      get api_v1_transactions_path, params: { page: 2 }, headers: auth
      body = JSON.parse(response.body)
      expect(body["transactions"].map { |t| t["id"] }).to eq([ old.id ])
      expect(body["meta"]).to include("total_count" => 51, "page" => 2, "page_limit" => 50)
    end
  end

  describe "POST /api/v1/transactions" do
    it "creates a transaction and returns it" do
      post api_v1_transactions_path,
           params: { kind: "expense", amount_cents: 89_90, date: Date.current.iso8601,
                     description: "Kahve", note: "espresso", account_id: account.id,
                     finance_category_id: category.id },
           headers: auth, as: :json

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body).to include(
        "kind" => "expense", "amount_cents" => 8_990, "date" => Date.current.iso8601,
        "description" => "Kahve", "note" => "espresso", "related_account" => nil
      )
      expect(body["account"]["id"]).to eq(account.id)
      expect(body["category"]["id"]).to eq(category.id)
      expect(user.transactions.count).to eq(1)
    end

    it "passes GAU amounts through untouched with subunit_to_unit 1" do
      gold = create(:account, user: user, currency: "GAU", name: "Altın")

      post api_v1_transactions_path,
           params: { kind: "expense", amount_cents: 412, date: Date.current.iso8601,
                     account_id: gold.id, finance_category_id: category.id },
           headers: auth, as: :json

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["amount_cents"]).to eq(412)
      expect(body["account"]).to include("currency" => "GAU", "subunit_to_unit" => 1)
      expect(user.transactions.last.amount_cents).to eq(412)
    end

    it "returns 422 with field-keyed errors for an invalid payload" do
      post api_v1_transactions_path,
           params: { kind: "transfer", amount_cents: 0, date: Date.current.iso8601, account_id: account.id },
           headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      errors = JSON.parse(response.body)["errors"]
      expect(errors["amount_cents"]).to be_an(Array)
      expect(errors["related_account_id"]).to be_an(Array)
    end

    it "404s when account_id belongs to another user" do
      foreign_account = create(:account)

      post api_v1_transactions_path,
           params: { kind: "expense", amount_cents: 10_00, date: Date.current.iso8601,
                     account_id: foreign_account.id, finance_category_id: category.id },
           headers: auth, as: :json

      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)["error"]).to eq("not_found")
      expect(user.transactions.count).to eq(0)
    end

    it "404s when finance_category_id belongs to another user" do
      foreign_category = create(:finance_category)

      post api_v1_transactions_path,
           params: { kind: "expense", amount_cents: 10_00, date: Date.current.iso8601,
                     account_id: account.id, finance_category_id: foreign_category.id },
           headers: auth, as: :json

      expect(response).to have_http_status(:not_found)
      expect(user.transactions.count).to eq(0)
    end
  end

  describe "PATCH /api/v1/transactions/:id" do
    it "updates and returns the transaction" do
      transaction = create(:transaction, user: user, account: account, finance_category: category)

      patch api_v1_transaction_path(transaction),
            params: { amount_cents: 77_00, description: "Güncellendi" },
            headers: auth, as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to include("id" => transaction.id, "amount_cents" => 7_700, "description" => "Güncellendi")
    end

    it "returns 422 for an invalid update" do
      transaction = create(:transaction, user: user, account: account, finance_category: category)

      patch api_v1_transaction_path(transaction), params: { amount_cents: 0 }, headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["errors"]).to have_key("amount_cents")
    end

    it "404s for another user's transaction" do
      other = create(:transaction)

      patch api_v1_transaction_path(other), params: { description: "hack" }, headers: auth, as: :json

      expect(response).to have_http_status(:not_found)
      expect(other.reload.description).to eq("Test transaction")
    end
  end

  describe "DELETE /api/v1/transactions/:id" do
    it "destroys the transaction and returns no content" do
      transaction = create(:transaction, user: user, account: account, finance_category: category)

      delete api_v1_transaction_path(transaction), headers: auth

      expect(response).to have_http_status(:no_content)
      expect(user.transactions.count).to eq(0)
    end

    it "404s for another user's transaction" do
      other = create(:transaction)

      delete api_v1_transaction_path(other), headers: auth

      expect(response).to have_http_status(:not_found)
      expect(Transaction.exists?(other.id)).to be(true)
    end
  end
end
