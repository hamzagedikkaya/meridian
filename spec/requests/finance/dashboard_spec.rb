require 'rails_helper'

RSpec.describe "Finance::Dashboard", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it "renders the dashboard" do
    get finance_root_path
    expect(response).to have_http_status(:success)
    expect(response.body).to include("Finance")
  end

  describe "category pie series" do
    let(:groceries)   { create(:finance_category, user: user, name: "Groceries",   kind: "expense", color: "#D4915A") }
    let(:bills)       { create(:finance_category, user: user, name: "Bills",       kind: "expense", color: "#A09B8E") }
    let(:salary)      { create(:finance_category, user: user, name: "Salary",      kind: "income",  color: "#6B8E5A") }
    let(:account)     { create(:account, user: user) }

    it "exposes pie datasets for 1m / 6m / 1y ranges in the chart card data attributes" do
      create(:transaction, user: user, account: account, finance_category: groceries, kind: "expense", amount_cents: 500_00, date: 5.days.ago)
      create(:transaction, user: user, account: account, finance_category: bills,     kind: "expense", amount_cents: 200_00, date: 3.months.ago)

      get finance_root_path

      expect(response.body).to match(/data-finance-chart-pie-m1-value="[^"]+"/)
      expect(response.body).to match(/data-finance-chart-pie-m6-value="[^"]+"/)
      expect(response.body).to match(/data-finance-chart-pie-y1-value="[^"]+"/)
    end

    it "groups expenses by category and excludes income from pie data" do
      create(:transaction, user: user, account: account, finance_category: groceries, kind: "expense", amount_cents: 500_00, date: 1.week.ago)
      create(:transaction, user: user, account: account, finance_category: salary,    kind: "income",  amount_cents: 5_000_00, date: 1.week.ago)

      get finance_root_path

      m1_payload = response.body[/data-finance-chart-pie-m1-value="([^"]+)"/, 1]
      expect(m1_payload).to include("Groceries")
      expect(m1_payload).not_to include("Salary")
    end

    it "scopes each range correctly (1m excludes older transactions)" do
      create(:transaction, user: user, account: account, finance_category: groceries, kind: "expense", amount_cents: 100_00, date: 2.days.ago)
      create(:transaction, user: user, account: account, finance_category: bills,     kind: "expense", amount_cents: 100_00, date: 4.months.ago)

      get finance_root_path

      m1_payload = response.body[/data-finance-chart-pie-m1-value="([^"]+)"/, 1]
      m6_payload = response.body[/data-finance-chart-pie-m6-value="([^"]+)"/, 1]

      expect(m1_payload).to include("Groceries")
      expect(m1_payload).not_to include("Bills")
      expect(m6_payload).to include("Bills")
    end
  end

  describe "GET /finance/category_pie (custom-range JSON)" do
    let(:account)   { create(:account, user: user) }
    let(:groceries) { create(:finance_category, user: user, name: "Groceries", kind: "expense") }

    it "returns aggregated expenses for the given window" do
      create(:transaction, user: user, account: account, finance_category: groceries, kind: "expense", amount_cents: 500_00, date: 5.days.ago)
      get finance_category_pie_path, params: { from: 7.days.ago.to_date.iso8601, to: Date.current.iso8601 }
      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body)
      expect(body["pie"].first).to include("name" => "Groceries", "amount" => 500_00)
    end

    it "400s on missing or inverted date range" do
      get finance_category_pie_path, params: { from: Date.current.iso8601 }
      expect(response).to have_http_status(:bad_request)

      get finance_category_pie_path, params: { from: Date.current.iso8601, to: 1.week.ago.to_date.iso8601 }
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "accounts sidebar" do
    it "lists active accounts and excludes archived ones" do
      create(:account, user: user, name: "Active Wallet")
      create(:account, user: user, name: "Old Wallet", archived_at: 1.day.ago)

      get finance_root_path

      expect(response.body).to include("Active Wallet")
      expect(response.body).not_to include("Old Wallet")
    end
  end

  describe "budgets card" do
    it "renders the budgets-this-month card when a budget exists" do
      category = create(:finance_category, user: user, name: "Groceries", kind: "expense")
      create(:budget, user: user, finance_category: category, monthly_limit_cents: 500_00)

      get finance_root_path

      expect(response.body).to include(I18n.t("finance.budgets.dashboard_title"))
      expect(response.body).to include("Groceries")
    end

    it "always shows the card with an empty-state link when there are no budgets" do
      get finance_root_path
      expect(response.body).to include(I18n.t("finance.budgets.dashboard_title"))
      expect(response.body).to include(I18n.t("finance.budgets.create_first"))
      expect(response.body).to include(finance_budgets_path)
    end
  end
end
