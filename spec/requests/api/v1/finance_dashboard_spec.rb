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

  describe "cumulative spend series" do
    let(:account) { create(:account, user: user) }

    def spend(cents, date, **attributes)
      create(:transaction, user: user, account: account, amount_cents: cents, date: date, **attributes)
    end

    it "is all zeros for a fresh user: one element per day so far, and every day of last month" do
      get api_v1_finance_dashboard_path, headers: auth

      expect(body["spend_cumulative_cents"]).to eq([ 0 ] * 15)
      expect(body["reference_cumulative_cents"]).to eq([ 0 ] * 30)
    end

    it "adds this month's expenses up day by day and ends on month.expense_cents" do
      spend(100_00, Date.new(2026, 7, 1))
      spend(200_00, Date.new(2026, 7, 15))
      spend(50_00, Date.new(2026, 7, 20))
      create(:transaction, :income, user: user, account: account, amount_cents: 999_00, date: Date.new(2026, 7, 2))
      create(:transaction, :transfer, user: user, account: account, amount_cents: 999_00, date: Date.new(2026, 7, 2))
      create(:transaction, amount_cents: 999_00, date: Date.new(2026, 7, 2))

      get api_v1_finance_dashboard_path, headers: auth

      expect(body["spend_cumulative_cents"]).to eq([ 100_00 ] * 14 + [ 350_00 ])
      expect(body["spend_cumulative_cents"].last).to eq(body["month"]["expense_cents"])
    end

    it "adds last month's expenses up over all of its days and ends on its total" do
      spend(40_00, Date.new(2026, 6, 3))
      spend(60_00, Date.new(2026, 6, 30))
      spend(70_00, Date.new(2026, 5, 31))

      get api_v1_finance_dashboard_path, headers: auth

      expect(body["reference_cumulative_cents"]).to eq([ 0, 0 ] + [ 40_00 ] * 27 + [ 100_00 ])
      expect(body["six_month_series"]["expense_cents"][4]).to eq(body["reference_cumulative_cents"].last)
    end
  end

  describe "currencies" do
    let(:lira) { create(:account, user: user, currency: "TRY") }
    let(:gold) { create(:account, user: user, currency: "GAU") }
    let(:dollars) { create(:account, user: user, currency: "USD", archived_at: Time.current) }

    before do
      create(:transaction, :income, user: user, account: lira, amount_cents: 5_000_00, date: Date.new(2026, 7, 10))
      create(:transaction, user: user, account: lira, amount_cents: 300_00, date: Date.new(2026, 7, 11), finance_category: nil)
      create(:transaction, :income, user: user, account: gold, amount_cents: 2, date: Date.new(2026, 7, 10))
      create(:transaction, user: user, account: gold, amount_cents: 5, date: Date.new(2026, 7, 11), finance_category: nil)
      create(:transaction, user: user, account: dollars, amount_cents: 40_00, date: Date.new(2026, 2, 1))
      create(:account, user: user, currency: "EUR")
    end

    it "keeps the totals, series and pie to accounts in the user's currency" do
      get api_v1_finance_dashboard_path, headers: auth

      expect(body["month"]).to eq("income_cents" => 5_000_00, "expense_cents" => 300_00, "net_cents" => 4_700_00)
      expect(body["year"]).to eq("income_cents" => 5_000_00, "expense_cents" => 300_00)
      expect(body["six_month_series"]["expense_cents"]).to eq([ 0, 0, 0, 0, 0, 300_00 ])
      expect(body["pie"].sum { |slice| slice["amount_cents"] }).to eq(300_00)
      expect(body["spend_cumulative_cents"].last).to eq(300_00)
    end

    it "lists every currency's month and year in totals_by_currency, the user's first" do
      get api_v1_finance_dashboard_path, headers: auth

      totals = body["totals_by_currency"]
      expect(totals.map { |row| row["currency"] }).to eq(%w[TRY EUR GAU USD])
      expect(totals.first.slice("month", "year")).to eq(body.slice("month", "year"))
      expect(totals[2]).to eq(
        "currency" => "GAU", "subunit_to_unit" => 1,
        "month" => { "income_cents" => 2, "expense_cents" => 5, "net_cents" => -3 },
        "year" => { "income_cents" => 2, "expense_cents" => 5 }
      )
      expect(totals[3]).to include("month" => { "income_cents" => 0, "expense_cents" => 0, "net_cents" => 0 },
                                   "year" => { "income_cents" => 0, "expense_cents" => 40_00 })
    end
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

    it "adds an uncategorized bucket, over the same whole month as month.expense_cents" do
      create(:transaction, user: user, finance_category: transport, amount_cents: 50_00, date: Date.new(2026, 7, 14))
      create(:transaction, user: user, finance_category: nil, amount_cents: 70_00, date: Date.new(2026, 7, 2))
      create(:transaction, user: user, finance_category: nil, amount_cents: 5_00, date: Date.new(2026, 7, 30))
      create(:transaction, user: user, finance_category: nil, amount_cents: 9_00, date: Date.new(2026, 6, 30))
      create(:transaction, :transfer, user: user, amount_cents: 999_00, date: Date.new(2026, 7, 3))

      get api_v1_finance_dashboard_path, headers: auth

      expect(body["pie"]).to eq([
        { "id" => 0, "name" => "Uncategorized", "color" => "#6E6A64", "amount_cents" => 75_00, "breakdown" => [], "uncategorized" => true },
        { "id" => transport.id, "name" => "Ulaşım", "color" => "#A09B8E", "amount_cents" => 50_00, "breakdown" => [] }
      ])
      expect(body["pie"].sum { |slice| slice["amount_cents"] }).to eq(body["month"]["expense_cents"])
    end

    it "counts a legacy row on another user's category as uncategorized, named in the user's language" do
      user.update!(locale: "tr")
      transaction = create(:transaction, user: user, amount_cents: 20_00, date: Date.new(2026, 7, 2))
      transaction.update_column(:finance_category_id, create(:finance_category).id)

      get api_v1_finance_dashboard_path, headers: auth

      expect(body["pie"]).to eq([
        { "id" => 0, "name" => "Kategorisiz", "color" => "#6E6A64", "amount_cents" => 20_00, "breakdown" => [], "uncategorized" => true }
      ])
    end
  end

  describe "budgets" do
    let(:market) { create(:finance_category, user: user, name: "Market", color: "#AA0000") }
    let(:transport) { create(:finance_category, user: user, name: "Ulaşım") }

    def expected_budgets(market_budget, transport_budget)
      [
        { "id" => market_budget.id, "finance_category_id" => market.id,
          "category" => { "id" => market.id, "name" => "Market", "color" => "#AA0000" }, "color" => "#AA0000", "custom_color" => nil,
          "limit_cents" => 40_000, "spent_cents" => 50_000, "remaining_cents" => -10_000, "over_by_cents" => 10_000,
          "percent_used" => 125, "bar_percent" => 100, "pace_percent" => 48, "projected_cents" => 103_333, "state" => "over" },
        { "id" => transport_budget.id, "finance_category_id" => transport.id,
          "category" => { "id" => transport.id, "name" => "Ulaşım", "color" => "#A09B8E" }, "color" => "#A09B8E", "custom_color" => nil,
          "limit_cents" => 100_000_000, "spent_cents" => 5_000, "remaining_cents" => 99_995_000, "over_by_cents" => 0,
          "percent_used" => 0, "bar_percent" => 0, "pace_percent" => 48, "projected_cents" => 10_333, "state" => "under" }
      ]
    end

    it "serializes month-to-date status with ids, pace and projection, over-budget first" do
      transport_budget = create(:budget, user: user, finance_category: transport, monthly_limit_cents: 1_000_000_00)
      market_budget = create(:budget, user: user, finance_category: market, monthly_limit_cents: 400_00)
      create(:budget)
      snacks = create(:finance_category, user: user, name: "Atıştırmalık", parent: market)
      create(:transaction, user: user, finance_category: snacks, amount_cents: 300_00, date: Date.new(2026, 7, 12))
      create(:transaction, user: user, finance_category: market, amount_cents: 200_00, date: Date.new(2026, 7, 13))
      create(:transaction, user: user, finance_category: transport, amount_cents: 50_00, date: Date.new(2026, 7, 14))

      get api_v1_finance_dashboard_path, headers: auth

      expect(body["budgets"]).to eq(expected_budgets(market_budget, transport_budget))
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
