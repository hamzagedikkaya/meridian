require "rails_helper"

RSpec.describe "Api::V1::Finance::Dashboard", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:auth) { { "Authorization" => "Bearer #{user.api_token}" } }

  def body = JSON.parse(response.body)

  before { travel_to Time.zone.local(2026, 7, 15, 12) }
  after { travel_back }

  it "returns JSON 401 without a token" do
    get api_v1_finance_dashboard_path

    expect(response).to have_http_status(:unauthorized)
    expect(body["error"]).to eq("unauthorized")
  end

  it "returns zeroed summaries and empty collections for a fresh user" do
    get api_v1_finance_dashboard_path, headers: auth

    expect(response).to have_http_status(:ok)
    expect(body["month"]).to eq("income_cents" => 0, "expense_cents" => 0, "net_cents" => 0)
    expect(body["year"]).to eq("income_cents" => 0, "expense_cents" => 0)
    expect(body["six_month_series"]["income_cents"]).to eq([ 0, 0, 0, 0, 0, 0 ])
    expect(body.values_at("pie", "budgets", "upcoming_subscriptions", "recent_transactions")).to all(eq([]))
  end

  it "sums month and year in integer cents, ignoring transfers and other users" do
    account = create(:account, user: user)
    create(:transaction, :income, user: user, account: account, amount_cents: 5_000_00, date: Date.new(2026, 7, 10))
    create(:transaction, user: user, account: account, amount_cents: 550_00, date: Date.new(2026, 7, 12))
    create(:transaction, :transfer, user: user, account: account, amount_cents: 700_00, date: Date.new(2026, 7, 11))
    create(:transaction, user: user, account: account, amount_cents: 300_00, date: Date.new(2026, 2, 10))
    create(:transaction, :income, amount_cents: 999_99, date: Date.new(2026, 7, 10))

    get api_v1_finance_dashboard_path, headers: auth

    expect(body["currency"]).to eq("TRY")
    expect(body["subunit_to_unit"]).to eq(100)
    expect(body["month"]).to eq("income_cents" => 500_000, "expense_cents" => 55_000, "net_cents" => 445_000)
    expect(body["year"]).to eq("income_cents" => 500_000, "expense_cents" => 85_000)
  end

  it "builds the six month series with ISO year-month labels and integer cents" do
    account = create(:account, user: user)
    create(:transaction, :income, user: user, account: account, amount_cents: 5_000_00, date: Date.new(2026, 7, 10))
    create(:transaction, user: user, account: account, amount_cents: 550_00, date: Date.new(2026, 7, 12))
    create(:transaction, user: user, account: account, amount_cents: 300_00, date: Date.new(2026, 2, 10))

    get api_v1_finance_dashboard_path, headers: auth

    expect(body["six_month_series"]).to eq(
      "labels" => [ "2026-02", "2026-03", "2026-04", "2026-05", "2026-06", "2026-07" ],
      "income_cents" => [ 0, 0, 0, 0, 0, 500_000 ],
      "expense_cents" => [ 30_000, 0, 0, 0, 0, 55_000 ]
    )
  end

  describe "pie" do
    let(:market) { create(:finance_category, user: user, name: "Market", color: "#AA0000") }
    let(:snacks) { create(:finance_category, user: user, name: "Atıştırmalık", parent: market) }
    let(:transport) { create(:finance_category, user: user, name: "Ulaşım") }

    def expected_pie
      [
        {
          "id" => market.id, "name" => "Market", "color" => "#AA0000", "amount_cents" => 50_000,
          "breakdown" => [
            { "id" => snacks.id, "name" => "Atıştırmalık", "amount_cents" => 30_000, "is_root" => false },
            { "id" => market.id, "name" => "Market", "amount_cents" => 20_000, "is_root" => true }
          ]
        },
        { "id" => transport.id, "name" => "Ulaşım", "color" => "#A09B8E", "amount_cents" => 5_000, "breakdown" => [] }
      ]
    end

    it "rolls current-month expenses up to root categories with a breakdown" do
      create(:transaction, user: user, finance_category: snacks, amount_cents: 300_00, date: Date.new(2026, 7, 12))
      create(:transaction, user: user, finance_category: market, amount_cents: 200_00, date: Date.new(2026, 7, 13))
      create(:transaction, user: user, finance_category: transport, amount_cents: 50_00, date: Date.new(2026, 7, 14))
      create(:transaction, user: user, finance_category: transport, amount_cents: 300_00, date: Date.new(2026, 2, 10))

      get api_v1_finance_dashboard_path, headers: auth

      expect(body["pie"]).to eq(expected_pie)
    end
  end

  describe "budgets" do
    let(:market) { create(:finance_category, user: user, name: "Market", color: "#AA0000") }
    let(:transport) { create(:finance_category, user: user, name: "Ulaşım") }

    def expected_budgets
      [
        { "category" => { "id" => market.id, "name" => "Market" }, "color" => "#AA0000",
          "limit_cents" => 40_000, "spent_cents" => 50_000, "remaining_cents" => -10_000,
          "percent_used" => 125, "pace_percent" => 48, "projected_cents" => 103_333, "state" => "over" },
        { "category" => { "id" => transport.id, "name" => "Ulaşım" }, "color" => "#A09B8E",
          "limit_cents" => 100_000_000, "spent_cents" => 5_000, "remaining_cents" => 99_995_000,
          "percent_used" => 0, "pace_percent" => 48, "projected_cents" => 10_333, "state" => "under" }
      ]
    end

    it "serializes month-to-date status with pace and projection, over-budget first" do
      create(:budget, user: user, finance_category: market, monthly_limit_cents: 400_00)
      create(:budget, user: user, finance_category: transport, monthly_limit_cents: 1_000_000_00)
      create(:budget)
      snacks = create(:finance_category, user: user, name: "Atıştırmalık", parent: market)
      create(:transaction, user: user, finance_category: snacks, amount_cents: 300_00, date: Date.new(2026, 7, 12))
      create(:transaction, user: user, finance_category: market, amount_cents: 200_00, date: Date.new(2026, 7, 13))
      create(:transaction, user: user, finance_category: transport, amount_cents: 50_00, date: Date.new(2026, 7, 14))

      get api_v1_finance_dashboard_path, headers: auth

      expect(body["budgets"]).to eq(expected_budgets)
    end
  end

  describe "upcoming subscriptions" do
    let(:wallet) { create(:account, user: user, name: "Wallet") }

    it "lists only active charges due within 30 days, with account briefs" do
      spotify = create(:subscription, user: user, account: wallet, name: "Spotify",
                       amount_cents: 120_00, next_charge_on: Date.new(2026, 7, 20))
      create(:subscription, user: user, account: wallet, next_charge_on: Date.new(2026, 9, 30))
      create(:subscription, user: user, account: wallet, active: false, next_charge_on: Date.new(2026, 7, 18))
      create(:subscription, next_charge_on: Date.new(2026, 7, 16))

      get api_v1_finance_dashboard_path, headers: auth

      expect(body["upcoming_subscriptions"]).to eq([
        { "id" => spotify.id, "name" => "Spotify", "amount_cents" => 12_000,
          "frequency" => "monthly", "next_charge_on" => "2026-07-20",
          "account" => { "id" => wallet.id, "name" => "Wallet", "color" => "#B8860B",
                         "currency" => "TRY", "subunit_to_unit" => 100 } }
      ])
    end
  end

  describe "recent transactions" do
    it "returns the latest transactions, transfers included" do
      account = create(:account, user: user)
      income = create(:transaction, :income, user: user, account: account, amount_cents: 5_000_00, date: Date.new(2026, 7, 10))
      transfer = create(:transaction, :transfer, user: user, account: account, amount_cents: 700_00, date: Date.new(2026, 7, 11))
      latest = create(:transaction, user: user, account: account, amount_cents: 50_00, date: Date.new(2026, 7, 14))
      create(:transaction, description: "Someone else's")

      get api_v1_finance_dashboard_path, headers: auth

      expect(body["recent_transactions"].map { |t| t["id"] }).to eq([ latest.id, transfer.id, income.id ])
      expect(body["recent_transactions"].first).to include("kind" => "expense", "amount_cents" => 5_000, "date" => "2026-07-14")
      expect(body["recent_transactions"][1]["related_account"]).to include("id", "name")
      expect(body["recent_transactions"][1]["category"]).to be_nil
    end
  end
end
