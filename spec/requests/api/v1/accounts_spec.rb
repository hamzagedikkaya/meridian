require "rails_helper"

RSpec.describe "Api::V1::Accounts", type: :request do
  let(:user) { create(:user) }
  let(:auth) { { "Authorization" => "Bearer #{user.api_token}" } }

  def body = JSON.parse(response.body)

  it "returns JSON 401 (not an HTML redirect) without a token" do
    get api_v1_accounts_path

    expect(response).to have_http_status(:unauthorized)
    expect(response.media_type).to eq("application/json")
    expect(JSON.parse(response.body)["error"]).to eq("unauthorized")
  end

  it "401s for a bogus token" do
    get api_v1_accounts_path, headers: { "Authorization" => "Bearer nope" }
    expect(response).to have_http_status(:unauthorized)
  end

  it "401s on every new account endpoint without a token" do
    account = create(:account, user: user)

    get api_v1_account_path(account)
    expect(response).to have_http_status(:unauthorized)
    post api_v1_accounts_path, params: { name: "Cash" }, as: :json
    expect(response).to have_http_status(:unauthorized)
    patch archive_api_v1_account_path(account)
    expect(response).to have_http_status(:unauthorized)
    delete api_v1_account_path(account)
    expect(response).to have_http_status(:unauthorized)
  end

  describe "GET /api/v1/accounts" do
    it "returns only the current user's active accounts, with balances" do
      create(:account, user: user, name: "Cash", currency: "TRY", initial_balance_cents: 1_000_00)
      create(:account, user: user, name: "Archived", archived_at: Time.current)
      create(:account, name: "Someone else's")

      get api_v1_accounts_path, headers: auth

      expect(response).to have_http_status(:ok)
      expect(body["accounts"].map { |a| a["name"] }).to eq([ "Cash" ])
      expect(body["accounts"].first).to include(
        "currency" => "TRY", "subunit_to_unit" => 100, "balance_cents" => 1_000_00,
        "archived" => false, "archived_at" => nil
      )
    end

    it "appends archived accounts, by name, with include_archived=true" do
      create(:account, user: user, name: "Zeta")
      create(:account, user: user, name: "Alpha")
      create(:account, user: user, name: "Old", archived_at: 2.days.ago)
      create(:account, user: user, name: "Ancient", archived_at: 1.day.ago)
      create(:account, name: "Someone else's", archived_at: 1.day.ago)

      get api_v1_accounts_path(include_archived: true), headers: auth

      expect(body["accounts"].map { |a| [ a["name"], a["archived"] ] })
        .to eq([ [ "Alpha", false ], [ "Zeta", false ], [ "Ancient", true ], [ "Old", true ] ])
    end

    it "422s for an include_archived that is not a boolean" do
      get api_v1_accounts_path(include_archived: "maybe"), headers: auth

      expect(response).to have_http_status(:unprocessable_content)
      expect(body).to include("code" => "invalid_parameter", "param" => "include_archived")
    end

    it "computes balances from income, expenses and transfers in both directions" do
      main = create(:account, user: user, name: "Main", initial_balance_cents: 1_000_00)
      savings = create(:account, user: user, name: "Savings")
      create(:transaction, :income, user: user, account: main, amount_cents: 500_00)
      create(:transaction, user: user, account: main, amount_cents: 200_00)
      create(:transaction, :transfer, user: user, account: main, related_account: savings, amount_cents: 100_00)
      create(:transaction, :transfer, user: user, account: savings, related_account: main, amount_cents: 50_00)

      get api_v1_accounts_path, headers: auth

      balances = body["accounts"].to_h { |a| [ a["name"], a["balance_cents"] ] }
      expect(balances).to eq("Main" => 1_250_00, "Savings" => 50_00)
    end
  end

  describe "GET /api/v1/accounts/:id" do
    it "opens an archived account with the counts a delete or currency change depends on" do
      account = create(:account, user: user, name: "Old card", archived_at: Time.zone.local(2026, 9, 1, 10))
      other = create(:account, user: user)
      create_list(:transaction, 2, user: user, account: account)
      create(:transaction, :transfer, user: user, account: other, related_account: account)
      create(:subscription, user: user, account: account)
      create(:goal, user: user, target_type: "financial", related: account)

      get api_v1_account_path(account), headers: auth

      expect(response).to have_http_status(:ok)
      expect(body["account"]).to include(
        "id" => account.id, "name" => "Old card", "archived" => true,
        "archived_at" => "2026-09-01T10:00:00.000Z",
        "transactions_count" => 2, "incoming_transfers_count" => 1, "subscriptions_count" => 1,
        "linked_goals_count" => 1, "deletable" => false, "currency_editable" => false
      )
    end

    it "marks an account with no activity deletable and its currency editable" do
      account = create(:account, user: user)

      get api_v1_account_path(account), headers: auth

      expect(body["account"]).to include(
        "transactions_count" => 0, "incoming_transfers_count" => 0, "subscriptions_count" => 0,
        "linked_goals_count" => 0, "deletable" => true, "currency_editable" => true
      )
    end

    it "404s for another user's account" do
      get api_v1_account_path(create(:account)), headers: auth

      expect(response).to have_http_status(:not_found)
      expect(body).to eq("error" => "not_found", "code" => "not_found")
    end
  end

  describe "POST /api/v1/accounts" do
    it "creates an account with the web form's defaults" do
      user.update!(currency: "USD")

      post api_v1_accounts_path, params: { name: "Wallet" }, headers: auth, as: :json

      expect(response).to have_http_status(:created)
      expect(body["account"]).to include(
        "name" => "Wallet", "account_type" => "cash", "currency" => "USD", "subunit_to_unit" => 100,
        "color" => "#B8860B", "initial_balance_cents" => 0, "balance_cents" => 0, "archived" => false
      )
      expect(user.accounts.count).to eq(1)
    end

    it "takes the opening balance in minor units, negative included, and upcases the currency" do
      post api_v1_accounts_path,
           params: { name: "Card", account_type: "credit_card", currency: " gau ", initial_balance_cents: -412, color: "#3366CC" },
           headers: auth, as: :json

      expect(response).to have_http_status(:created)
      expect(body["account"]).to include(
        "account_type" => "credit_card", "currency" => "GAU", "subunit_to_unit" => 1,
        "initial_balance_cents" => -412, "balance_cents" => -412, "color" => "#3366CC"
      )
    end

    it "ignores archived_at: a new account is always active" do
      post api_v1_accounts_path, params: { name: "Cash", archived_at: Time.current.iso8601 }, headers: auth, as: :json

      expect(body["account"]["archived"]).to be(false)
      expect(user.accounts.active.count).to eq(1)
    end

    it "422s with every field error at once" do
      post api_v1_accounts_path,
           params: { name: "", account_type: "wallet", currency: "XYZ", color: "red" }, headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(body["code"]).to eq("validation_failed")
      expect(body["details"]).to include(
        "name" => [ { "error" => "blank" } ],
        "account_type" => [ { "error" => "inclusion", "value" => "wallet" } ],
        "currency" => [ { "error" => "inclusion", "value" => "XYZ" } ],
        "color" => [ { "error" => "invalid" } ]
      )
      expect(user.accounts.count).to eq(0)
    end

    it "words the errors in the user's language" do
      user.update!(locale: "tr")

      post api_v1_accounts_path, params: { name: "Kasa", currency: "XYZ" }, headers: auth, as: :json

      expect(body["errors"]).to eq("currency" => [ "Para birimi geçerli bir seçenek değil" ])
    end

    it "422s invalid_parameter for an opening balance that is not a whole number" do
      post api_v1_accounts_path, params: { name: "Cash", initial_balance_cents: 12.5 }, headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(body).to include("code" => "invalid_parameter", "param" => "initial_balance_cents")
    end

    it "422s value_out_of_range for an opening balance the 4-byte column cannot hold" do
      post api_v1_accounts_path, params: { name: "House", initial_balance_cents: 3_000_000_000 }, headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(body["code"]).to eq("value_out_of_range")
      expect(user.accounts.count).to eq(0)
    end
  end

  describe "PATCH /api/v1/accounts/:id" do
    it "changes only the fields sent and recomputes the balance" do
      account = create(:account, user: user, name: "Cash", color: "#111111", initial_balance_cents: 100_00)
      create(:transaction, user: user, account: account, amount_cents: 30_00)

      patch api_v1_account_path(account), params: { name: "Wallet", initial_balance_cents: 200_00 }, headers: auth, as: :json

      expect(response).to have_http_status(:ok)
      expect(body["account"]).to include(
        "name" => "Wallet", "color" => "#111111", "initial_balance_cents" => 200_00, "balance_cents" => 170_00
      )
    end

    it "changes the currency of an account nothing is recorded on" do
      account = create(:account, user: user, currency: "TRY")

      patch api_v1_account_path(account), params: { currency: "usd" }, headers: auth, as: :json

      expect(response).to have_http_status(:ok)
      expect(account.reload.currency).to eq("USD")
    end

    it "refuses a currency change once the account has transactions" do
      account = create(:account, user: user, name: "Cash", currency: "TRY")
      create(:transaction, user: user, account: account)

      patch api_v1_account_path(account), params: { name: "Gold", currency: "GAU" }, headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(body).to include("code" => "currency_locked", "errors" => { "currency" => [ I18n.t("api.errors.currency_locked") ] })
      expect(account.reload).to have_attributes(name: "Cash", currency: "TRY")
    end

    it "refuses a currency change once the account has a subscription or an incoming transfer" do
      with_subscription = create(:account, user: user)
      create(:subscription, user: user, account: with_subscription)
      with_transfer = create(:account, user: user)
      create(:transaction, :transfer, user: user, related_account: with_transfer)

      [ with_subscription, with_transfer ].each do |account|
        patch api_v1_account_path(account), params: { currency: "EUR" }, headers: auth, as: :json
        expect(body["code"]).to eq("currency_locked")
      end
    end

    it "lets a lowercase code stored by the web be normalized" do
      account = create(:account, user: user)
      account.update_column(:currency, "try")
      create(:transaction, user: user, account: account)

      patch api_v1_account_path(account), params: { currency: "TRY" }, headers: auth, as: :json

      expect(response).to have_http_status(:ok)
      expect(account.reload.currency).to eq("TRY")
    end

    it "404s for another user's account" do
      other = create(:account, name: "Theirs")

      patch api_v1_account_path(other), params: { name: "Mine" }, headers: auth, as: :json

      expect(response).to have_http_status(:not_found)
      expect(other.reload.name).to eq("Theirs")
    end
  end

  describe "DELETE /api/v1/accounts/:id" do
    it "deletes an account no transaction touches, with its subscriptions, and unlinks its goals" do
      account = create(:account, user: user)
      subscription = create(:subscription, user: user, account: account)
      goal = create(:goal, user: user, target_type: "financial", related: account)

      delete api_v1_account_path(account), headers: auth

      expect(response).to have_http_status(:no_content)
      expect(Account.exists?(account.id)).to be(false)
      expect(Subscription.exists?(subscription.id)).to be(false)
      expect(goal.reload).to have_attributes(related_type: nil, related_id: nil)
    end

    it "refuses with has_transactions while the account has its own transactions" do
      account = create(:account, user: user)
      create(:transaction, user: user, account: account)

      delete api_v1_account_path(account), headers: auth

      expect(response).to have_http_status(:unprocessable_content)
      expect(body).to include(
        "code" => "has_transactions", "transactions_count" => 1, "incoming_transfers_count" => 0,
        "errors" => { "base" => [ I18n.t("api.errors.has_transactions") ] }
      )
      expect(Account.exists?(account.id)).to be(true)
    end

    it "refuses while another account's transfer points at it" do
      account = create(:account, user: user)
      transfer = create(:transaction, :transfer, user: user, related_account: account)

      delete api_v1_account_path(account), headers: auth

      expect(body).to include("code" => "has_transactions", "transactions_count" => 0, "incoming_transfers_count" => 1)
      expect(transfer.reload.related_account_id).to eq(account.id)
    end

    it "refuses, leaving everything in place, when a transaction appears after the check" do
      account = create(:account, user: user)
      subscription = create(:subscription, user: user, account: account)
      allow(Account).to receive(:transaction).and_wrap_original do |original, *args, &block|
        create(:transaction, user: user, account: account)
        original.call(*args, &block)
      end

      delete api_v1_account_path(account), headers: auth

      expect(body).to include("code" => "has_transactions", "transactions_count" => 1)
      expect(Subscription.exists?(subscription.id)).to be(true)
    end

    it "404s for another user's account" do
      other = create(:account)

      delete api_v1_account_path(other), headers: auth

      expect(response).to have_http_status(:not_found)
      expect(Account.exists?(other.id)).to be(true)
    end
  end

  describe "PATCH /api/v1/accounts/:id/archive and /unarchive" do
    it "archives: the account leaves the default list, its transactions stay" do
      account = create(:account, user: user)
      create(:transaction, user: user, account: account)

      patch archive_api_v1_account_path(account), headers: auth

      expect(response).to have_http_status(:ok)
      expect(body["account"]).to include("id" => account.id, "archived" => true)
      expect(user.accounts.active).to be_empty
      expect(account.transactions.count).to eq(1)
    end

    it "is idempotent and keeps the first archive time" do
      archived_at = Time.zone.local(2026, 9, 1, 10)
      account = create(:account, user: user, archived_at: archived_at)

      patch archive_api_v1_account_path(account), headers: auth

      expect(response).to have_http_status(:ok)
      expect(account.reload.archived_at).to eq(archived_at)
    end

    it "unarchives, also idempotently" do
      account = create(:account, user: user, archived_at: 1.day.ago)

      2.times { patch unarchive_api_v1_account_path(account), headers: auth }

      expect(response).to have_http_status(:ok)
      expect(body["account"]).to include("archived" => false, "archived_at" => nil)
      expect(account.reload.archived_at).to be_nil
    end

    it "404s for another user's account" do
      other = create(:account)

      patch archive_api_v1_account_path(other), headers: auth
      expect(response).to have_http_status(:not_found)
      patch unarchive_api_v1_account_path(other), headers: auth
      expect(response).to have_http_status(:not_found)
      expect(other.reload.archived_at).to be_nil
    end
  end
end
