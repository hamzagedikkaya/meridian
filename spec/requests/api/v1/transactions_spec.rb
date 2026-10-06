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
    context "with a mix of the user's and another user's transactions" do
      let!(:expense) do
        create(:transaction, user: user, account: account, finance_category: category,
               amount_cents: 250_00, date: Date.current, description: "Groceries", note: "weekly")
      end

      before do
        create(:transaction, :income, user: user, account: account, amount_cents: 1_000_00, date: Date.current - 1)
        create(:transaction, :transfer, user: user, account: account, amount_cents: 300_00, date: Date.current - 2)
        create(:transaction, description: "Someone else's")
        get api_v1_transactions_path, headers: auth
      end

      it "lists only the user's transactions, recent first, with meta" do
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["transactions"].size).to eq(3)
        expect(body["transactions"].first["id"]).to eq(expense.id)
        expect(body["meta"]).to eq(
          "total_count" => 3, "page" => 1, "page_limit" => 50,
          "filtered_income_cents" => 100_000, "filtered_expense_cents" => 25_000
        )
      end

      it "serializes a transaction with its nested account and category" do
        first = JSON.parse(response.body)["transactions"].first
        expect(first).to eq(
          "id" => expense.id, "kind" => "expense", "amount_cents" => 25_000,
          "date" => Date.current.iso8601, "description" => "Groceries", "note" => "weekly",
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
      end
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

    describe "q" do
      def ids_for(params)
        get api_v1_transactions_path, params: params, headers: auth
        JSON.parse(response.body)["transactions"].map { |t| t["id"] }
      end

      it "matches the description or the note in any case, with the other filters and meta totals" do
        by_description = create(:transaction, user: user, account: account, description: "Kahve dükkanı", amount_cents: 85_00)
        by_note = create(:transaction, :income, user: user, account: account, description: "Maaş", note: "kahVE parası", amount_cents: 10_00)
        create(:transaction, user: user, account: account, description: "Market")
        create(:transaction, description: "Kahve", note: "someone else's")

        expect(ids_for(q: "KAHVE")).to contain_exactly(by_description.id, by_note.id)
        expect(JSON.parse(response.body)["meta"]).to include(
          "total_count" => 2, "filtered_income_cents" => 10_00, "filtered_expense_cents" => 85_00
        )
        expect(ids_for(q: " kahve ", kind: "expense")).to eq([ by_description.id ])
      end

      it "ignores the case of Turkish letters" do
        candy = create(:transaction, user: user, account: account, description: "Şekerci", note: nil)
        create(:transaction, user: user, account: account, description: "Market", note: "IĞDIR")

        expect(ids_for(q: "ŞEKER")).to eq([ candy.id ])
        expect(ids_for(q: "ığdır").size).to eq(1)
      end

      it "reads % and _ literally, ignores a blank q and 422s for a q that is not a string" do
        percent = create(:transaction, user: user, account: account, description: "100% iade")
        create(:transaction, user: user, account: account, description: "1000 iade")

        expect(ids_for(q: "0%")).to eq([ percent.id ])
        expect(ids_for(q: "_")).to be_empty
        expect(ids_for(q: "  ").size).to eq(2)

        get api_v1_transactions_path, params: { q: [ "kahve" ] }, headers: auth
        expect(response).to have_http_status(:unprocessable_content)
        expect(JSON.parse(response.body)).to include("code" => "invalid_parameter", "param" => "q")
      end
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

    it "422s with code value_out_of_range for an amount the 4-byte column cannot hold" do
      post api_v1_transactions_path,
           params: { kind: "expense", amount_cents: 3_000_000_000, date: Date.current.iso8601,
                     account_id: account.id, finance_category_id: category.id },
           headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)).to include("code" => "value_out_of_range")
      expect(user.transactions.count).to eq(0)
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

  describe "GET /api/v1/transactions/:id" do
    def body = JSON.parse(response.body)

    it "401s without a token" do
      get api_v1_transaction_path(create(:transaction, user: user))

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns the transaction as the list does, plus its linkage" do
      transaction = create(:transaction, user: user, account: account, finance_category: category, note: "n")

      get api_v1_transaction_path(transaction), headers: auth

      expect(response).to have_http_status(:ok)
      expect(body["transaction"]).to include(
        "id" => transaction.id, "kind" => "expense", "note" => "n", "parent_transaction_id" => nil, "linked" => nil,
        "category" => hash_including("id" => category.id), "account" => hash_including("id" => account.id)
      )
    end

    it "shows a web-linked pair from both sides" do
      gold = create(:account, user: user, name: "Altın", currency: "GAU")
      parent = create(:transaction, user: user, account: account, amount_cents: 5_000_00, description: "Altın alımı")
      child = create(:transaction, :income, user: user, account: gold, amount_cents: 2, parent_transaction: parent,
                                            description: "Altın alımı")

      get api_v1_transaction_path(parent), headers: auth
      expect(body["transaction"]["linked"]).to eq(
        "id" => child.id, "kind" => "income", "amount_cents" => 2, "date" => child.date.iso8601, "description" => "Altın alımı",
        "account" => { "id" => gold.id, "name" => "Altın", "color" => "#B8860B", "currency" => "GAU", "subunit_to_unit" => 1 },
        "relation" => "child"
      )

      get api_v1_transaction_path(child), headers: auth
      expect(body["transaction"]).to include("parent_transaction_id" => parent.id, "linked" => hash_including("id" => parent.id, "relation" => "parent"))
    end

    it "404s for another user's transaction" do
      get api_v1_transaction_path(create(:transaction)), headers: auth

      expect(response).to have_http_status(:not_found)
      expect(body).to eq("error" => "not_found", "code" => "not_found")
    end
  end

  describe "uncategorized transactions" do
    it "creates an expense without a category" do
      post api_v1_transactions_path,
           params: { kind: "expense", amount_cents: 45_00, date: Date.current.iso8601, account_id: account.id, finance_category_id: nil },
           headers: auth, as: :json

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["category"]).to be_nil
      expect(user.transactions.last.finance_category_id).to be_nil
    end

    it "clears a transaction's category with finance_category_id null" do
      transaction = create(:transaction, user: user, account: account, finance_category: category)

      patch api_v1_transaction_path(transaction), params: { finance_category_id: nil }, headers: auth, as: :json

      expect(response).to have_http_status(:ok)
      expect(transaction.reload.finance_category_id).to be_nil
    end

    it "lists only uncategorized transactions with category_id=none" do
      uncategorized = create(:transaction, user: user, account: account, finance_category: nil)
      create(:transaction, user: user, account: account, finance_category: category)
      create(:transaction, finance_category: nil)

      get api_v1_transactions_path(category_id: "none", kind: "expense"), headers: auth

      expect(JSON.parse(response.body)["transactions"].map { |t| t["id"] }).to eq([ uncategorized.id ])
    end
  end

  describe "transfers" do
    def transfer(params)
      post api_v1_transactions_path,
           params: { kind: "transfer", amount_cents: 100_00, date: Date.current.iso8601, account_id: account.id }.merge(params),
           headers: auth, as: :json
      JSON.parse(response.body)
    end

    it "moves money to another account in the same currency" do
      savings = create(:account, user: user, currency: "TRY")

      expect(transfer(related_account_id: savings.id)).to include("kind" => "transfer", "related_account" => hash_including("id" => savings.id))
      expect(response).to have_http_status(:created)
    end

    it "refuses the same account and an account in another currency" do
      gold = create(:account, user: user, currency: "GAU")

      expect(transfer(related_account_id: account.id)["details"]).to eq("related_account_id" => [ { "error" => "same_account" } ])
      expect(transfer(related_account_id: gold.id)["details"]).to eq("related_account_id" => [ { "error" => "currency_mismatch" } ])
      expect(user.transactions.count).to eq(0)
    end

    it "refuses an edit that points a transfer at an account in another currency" do
      existing = create(:transaction, :transfer, user: user, account: account)

      patch api_v1_transaction_path(existing), params: { related_account_id: create(:account, user: user, currency: "USD").id },
                                               headers: auth, as: :json

      expect(JSON.parse(response.body)["details"]).to eq("related_account_id" => [ { "error" => "currency_mismatch" } ])
    end

    it "keeps an older transfer between currencies editable" do
      existing = create(:transaction, :transfer, user: user, account: account)
      existing.related_account.update_column(:currency, "USD")

      patch api_v1_transaction_path(existing), params: { description: "Renamed" }, headers: auth, as: :json

      expect(response).to have_http_status(:ok)
      expect(existing.reload.description).to eq("Renamed")
    end

    it "adds transfers into the account to its history with include_incoming_transfers=true" do
      own = create(:transaction, user: user, account: account, date: Date.current)
      incoming = create(:transaction, :transfer, user: user, related_account: account, date: Date.current - 1)
      create(:transaction, :transfer, user: user)

      get api_v1_transactions_path(account_id: account.id), headers: auth
      expect(JSON.parse(response.body)["transactions"].map { |t| t["id"] }).to eq([ own.id ])

      get api_v1_transactions_path(account_id: account.id, include_incoming_transfers: true), headers: auth
      expect(JSON.parse(response.body)["transactions"].map { |t| t["id"] }).to eq([ own.id, incoming.id ])
    end
  end
end
