require "rails_helper"

RSpec.describe "Api::V1::Subscriptions", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:auth) { { "Authorization" => "Bearer #{user.api_token}" } }
  let(:wallet) { create(:account, user: user, name: "Wallet") }
  let(:media) { create(:finance_category, user: user, name: "Medya") }

  def body = JSON.parse(response.body)

  def create_subscription(params)
    post api_v1_subscriptions_path, params: params, headers: auth, as: :json
  end

  before { travel_to Time.zone.local(2026, 7, 15, 12) }
  after { travel_back }

  it "401s without a token" do
    subscription = create(:subscription, user: user)

    get api_v1_subscriptions_path
    expect(response).to have_http_status(:unauthorized)
    get api_v1_subscription_path(subscription)
    expect(response).to have_http_status(:unauthorized)
    post api_v1_subscriptions_path, params: { name: "X" }, as: :json
    expect(response).to have_http_status(:unauthorized)
    post charge_api_v1_subscription_path(subscription)
    expect(response).to have_http_status(:unauthorized)
  end

  describe "GET /api/v1/subscriptions" do
    before do
      dollars = create(:account, user: user, currency: "USD")
      create(:subscription, user: user, account: wallet, name: "Later", amount_cents: 100_00, next_charge_on: Date.new(2026, 8, 1))
      create(:subscription, user: user, account: wallet, name: "Sooner", amount_cents: 52_00, frequency: "weekly",
                            next_charge_on: Date.new(2026, 7, 20))
      create(:subscription, user: user, account: dollars, name: "Cloud", amount_cents: 120_00, frequency: "yearly")
      create(:subscription, user: user, account: wallet, name: "Zzz paused", active: false)
      create(:subscription, user: user, account: wallet, name: "Aaa paused", active: false)
      create(:subscription, name: "Someone else's")
    end

    it "lists active subscriptions by next charge, then inactive ones by name" do
      get api_v1_subscriptions_path, headers: auth

      expect(response).to have_http_status(:ok)
      expect(body["active"].map { |s| s["name"] }).to eq([ "Sooner", "Later", "Cloud" ])
      expect(body["inactive"].map { |s| s["name"] }).to eq([ "Aaa paused", "Zzz paused" ])
    end

    it "totals the active ones per currency, the user's currency first" do
      get api_v1_subscriptions_path, headers: auth

      expect(body["totals"]).to eq([
        { "currency" => "TRY", "subunit_to_unit" => 100, "monthly_cents" => 100_00 + 225_33, "yearly_cents" => 1_200_00 + 2_704_00 },
        { "currency" => "USD", "subunit_to_unit" => 100, "monthly_cents" => 10_00, "yearly_cents" => 120_00 }
      ])
    end
  end

  describe "GET /api/v1/subscriptions/:id" do
    it "returns every field, with the account brief and the category" do
      subscription = create(:subscription, user: user, account: wallet, finance_category: media, name: "Spotify",
                                           vendor: "Spotify AB", amount_cents: 60_00, note: "aile", color: "#1DB954",
                                           start_date: Date.new(2026, 1, 3), next_charge_on: Date.new(2026, 8, 3))

      get api_v1_subscription_path(subscription), headers: auth

      expect(body["subscription"]).to eq(
        "id" => subscription.id, "name" => "Spotify", "vendor" => "Spotify AB", "amount_cents" => 60_00,
        "frequency" => "monthly", "next_charge_on" => "2026-08-03", "start_date" => "2026-01-03", "end_date" => nil,
        "active" => true, "color" => "#1DB954", "note" => "aile", "monthly_amount_cents" => 60_00, "yearly_amount_cents" => 720_00,
        "account" => { "id" => wallet.id, "name" => "Wallet", "color" => "#B8860B", "currency" => "TRY", "subunit_to_unit" => 100 },
        "category" => { "id" => media.id, "name" => "Medya", "kind" => "expense", "color" => "#A09B8E", "parent_id" => nil, "position" => 0 }
      )
    end

    it "404s for another user's subscription" do
      get api_v1_subscription_path(create(:subscription)), headers: auth

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/subscriptions" do
    it "creates one with the web form's defaults: active, monthly, from today, next charge in a month" do
      create_subscription(name: "Netflix", account_id: wallet.id, amount_cents: 229_99)

      expect(response).to have_http_status(:created)
      expect(body["subscription"]).to include(
        "name" => "Netflix", "amount_cents" => 229_99, "frequency" => "monthly", "active" => true,
        "start_date" => "2026-07-15", "next_charge_on" => "2026-08-15", "end_date" => nil, "category" => nil, "color" => "#B8860B"
      )
    end

    it "puts the first charge on the start date's cycle, after today" do
      { [ "2026-07-10", "weekly" ] => "2026-07-17", [ "2025-01-31", "monthly" ] => "2026-07-31",
        [ "2024-07-15", "yearly" ] => "2027-07-15", [ "2026-09-01", "monthly" ] => "2026-09-01" }.each do |(start, frequency), first|
        create_subscription(name: "S", account_id: wallet.id, amount_cents: 1, start_date: start, frequency: frequency)
        expect(body["subscription"]["next_charge_on"]).to eq(first), "for #{frequency} from #{start}"
      end
    end

    it "keeps the dates and category it is given" do
      create_subscription(name: "Gym", account_id: wallet.id, amount_cents: 900_00, frequency: "yearly", finance_category_id: media.id,
                          start_date: "2026-01-01", next_charge_on: "2027-01-01", end_date: "2027-12-31", active: false)

      expect(response).to have_http_status(:created)
      expect(body["subscription"]).to include(
        "frequency" => "yearly", "start_date" => "2026-01-01", "next_charge_on" => "2027-01-01", "end_date" => "2027-12-31",
        "active" => false, "monthly_amount_cents" => 75_00
      )
      expect(body["subscription"]["category"]["id"]).to eq(media.id)
    end

    it "422s with every field error at once" do
      salary = create(:finance_category, user: user, kind: "income")

      create_subscription(name: "", account_id: wallet.id, amount_cents: 0, frequency: "daily", finance_category_id: salary.id,
                          start_date: "2026-07-01", end_date: "2026-06-30", color: "green")

      expect(response).to have_http_status(:unprocessable_content)
      expect(body["details"].keys).to contain_exactly("name", "amount_cents", "frequency", "finance_category_id", "end_date", "color")
      expect(body["details"]).to include("finance_category_id" => [ { "error" => "must_be_expense" } ],
                                         "end_date" => [ { "error" => "before_start_date" } ])
    end

    it "422s for a missing account" do
      create_subscription(name: "X", amount_cents: 100)

      expect(body["details"]).to eq("account" => [ { "error" => "blank" } ])
    end

    it "422s invalid_date for a date that is not YYYY-MM-DD or does not exist" do
      [ "15.08.2026", "2026-02-30", "2026-08" ].each do |date|
        create_subscription(name: "X", account_id: wallet.id, amount_cents: 100, next_charge_on: date)
        expect(body).to include("code" => "invalid_date", "param" => "next_charge_on"), "for #{date}"
      end
      expect(user.subscriptions.count).to eq(0)
    end

    it "422s invalid_parameter for an amount or active flag it cannot read" do
      create_subscription(name: "X", account_id: wallet.id, amount_cents: "9.99")
      expect(body).to include("code" => "invalid_parameter", "param" => "amount_cents")

      create_subscription(name: "X", account_id: wallet.id, amount_cents: 100, active: nil)
      expect(body).to include("code" => "invalid_parameter", "param" => "active")
    end

    it "404s for another user's account or category" do
      create_subscription(name: "X", account_id: create(:account).id, amount_cents: 100)
      expect(response).to have_http_status(:not_found)

      create_subscription(name: "X", account_id: wallet.id, amount_cents: 100, finance_category_id: create(:finance_category).id)
      expect(response).to have_http_status(:not_found)
      expect(Subscription.count).to eq(0)
    end
  end

  describe "PATCH /api/v1/subscriptions/:id" do
    it "pauses it, changes only the fields sent and clears with null" do
      subscription = create(:subscription, user: user, account: wallet, finance_category: media, name: "Spotify",
                                           end_date: Date.new(2027, 1, 1))

      patch api_v1_subscription_path(subscription), params: { active: false, end_date: nil, finance_category_id: nil },
                                                    headers: auth, as: :json

      expect(response).to have_http_status(:ok)
      expect(body["subscription"]).to include("name" => "Spotify", "active" => false, "end_date" => nil, "category" => nil)
      expect(user.subscriptions.upcoming).to be_empty
    end

    it "needs the amount again to move to an account in another currency" do
      subscription = create(:subscription, user: user, account: wallet, amount_cents: 100_00)
      gold = create(:account, user: user, currency: "GAU")

      patch api_v1_subscription_path(subscription), params: { account_id: gold.id }, headers: auth, as: :json
      expect(body).to include("code" => "amount_required", "errors" => { "amount_cents" => [ I18n.t("api.errors.amount_required") ] })
      expect(subscription.reload.account_id).to eq(wallet.id)

      patch api_v1_subscription_path(subscription), params: { account_id: gold.id, amount_cents: 2 }, headers: auth, as: :json
      expect(response).to have_http_status(:ok)
      expect(body["subscription"]).to include("amount_cents" => 2, "account" => hash_including("currency" => "GAU"))
    end

    it "moves to another account in the same currency without the amount" do
      subscription = create(:subscription, user: user, account: wallet)
      bank = create(:account, user: user, currency: "TRY")

      patch api_v1_subscription_path(subscription), params: { account_id: bank.id }, headers: auth, as: :json

      expect(response).to have_http_status(:ok)
      expect(subscription.reload.account_id).to eq(bank.id)
    end

    it "keeps an older row with an income category editable" do
      subscription = create(:subscription, user: user, account: wallet)
      subscription.update_column(:finance_category_id, create(:finance_category, user: user, kind: "income").id)

      patch api_v1_subscription_path(subscription), params: { name: "Renamed" }, headers: auth, as: :json

      expect(response).to have_http_status(:ok)
      expect(subscription.reload.name).to eq("Renamed")
    end

    it "404s for another user's subscription or account" do
      other = create(:subscription, name: "Theirs")
      mine = create(:subscription, user: user, account: wallet)

      patch api_v1_subscription_path(other), params: { name: "Mine" }, headers: auth, as: :json
      expect(response).to have_http_status(:not_found)
      patch api_v1_subscription_path(mine), params: { account_id: other.account_id, amount_cents: 1 }, headers: auth, as: :json
      expect(response).to have_http_status(:not_found)
      expect(other.reload.name).to eq("Theirs")
    end
  end

  describe "DELETE /api/v1/subscriptions/:id" do
    it "deletes it and keeps the transactions recorded for it" do
      subscription = create(:subscription, user: user, account: wallet, next_charge_on: Date.new(2026, 7, 1))
      transaction = Finance::ProcessSubscriptions.charge!(subscription)

      delete api_v1_subscription_path(subscription), headers: auth

      expect(response).to have_http_status(:no_content)
      expect(Subscription.exists?(subscription.id)).to be(false)
      expect(Transaction.exists?(transaction.id)).to be(true)
    end

    it "404s for another user's subscription" do
      other = create(:subscription)

      delete api_v1_subscription_path(other), headers: auth

      expect(response).to have_http_status(:not_found)
      expect(Subscription.exists?(other.id)).to be(true)
    end
  end

  describe "POST /api/v1/subscriptions/:id/charge" do
    let(:subscription) do
      create(:subscription, user: user, account: wallet, finance_category: media, name: "Spotify",
                            amount_cents: 60_00, next_charge_on: Date.new(2026, 7, 3))
    end

    it "records an overdue charge on its due date and moves the next charge a period on" do
      post charge_api_v1_subscription_path(subscription), headers: auth

      expect(response).to have_http_status(:created)
      expect(body["transaction"]).to include("kind" => "expense", "amount_cents" => 60_00, "date" => "2026-07-03",
                                             "description" => "Spotify", "category" => hash_including("id" => media.id))
      expect(body["subscription"]["next_charge_on"]).to eq("2026-08-03")
      expect(wallet.transactions.count).to eq(1)
    end

    it "dates a payment made before the due date today, or on the date sent" do
      subscription.update!(next_charge_on: Date.new(2026, 7, 20))

      post charge_api_v1_subscription_path(subscription), headers: auth
      expect(body["transaction"]["date"]).to eq("2026-07-15")
      expect(body["subscription"]["next_charge_on"]).to eq("2026-08-20")

      post charge_api_v1_subscription_path(subscription), params: { date: "2026-07-14" }, headers: auth, as: :json
      expect(body["transaction"]["date"]).to eq("2026-07-14")
    end

    it "refuses an inactive subscription or one without a next charge date" do
      subscription.update!(active: false)
      post charge_api_v1_subscription_path(subscription), headers: auth
      expect(body).to include("code" => "not_chargeable", "reason" => "inactive")

      subscription.update!(active: true, next_charge_on: nil)
      post charge_api_v1_subscription_path(subscription), headers: auth
      expect(body).to include("code" => "not_chargeable", "reason" => "no_next_charge")
      expect(Transaction.count).to eq(0)
    end

    it "422s invalid_date for an unreadable date and 404s for another user's subscription" do
      post charge_api_v1_subscription_path(subscription), params: { date: "yesterday" }, headers: auth, as: :json
      expect(body).to include("code" => "invalid_date", "param" => "date")

      post charge_api_v1_subscription_path(create(:subscription, next_charge_on: Date.new(2026, 7, 1))), headers: auth
      expect(response).to have_http_status(:not_found)
      expect(Transaction.count).to eq(0)
    end
  end
end
