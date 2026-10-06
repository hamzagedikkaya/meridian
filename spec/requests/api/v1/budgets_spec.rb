require "rails_helper"

RSpec.describe "Api::V1::Budgets", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:auth) { { "Authorization" => "Bearer #{user.api_token}" } }
  let(:market) { create(:finance_category, user: user, name: "Market", color: "#AA0000") }

  def body = JSON.parse(response.body)

  before { travel_to Time.zone.local(2026, 7, 15, 12) }
  after { travel_back }

  it "401s without a token" do
    budget = create(:budget, user: user)

    get api_v1_budgets_path
    expect(response).to have_http_status(:unauthorized)
    post api_v1_budgets_path, params: { finance_category_id: market.id, monthly_limit_cents: 100 }, as: :json
    expect(response).to have_http_status(:unauthorized)
    patch api_v1_budget_path(budget), params: { monthly_limit_cents: 100 }, as: :json
    expect(response).to have_http_status(:unauthorized)
    delete api_v1_budget_path(budget)
    expect(response).to have_http_status(:unauthorized)
  end

  describe "GET /api/v1/budgets" do
    let(:transport) { create(:finance_category, user: user, name: "Ulaşım", position: 2) }
    let!(:market_budget) { create(:budget, user: user, finance_category: market, monthly_limit_cents: 400_00, color: "#00FF00") }

    before do
      snacks = create(:finance_category, user: user, name: "Atıştırmalık", parent: market)
      create(:budget, user: user, finance_category: transport, monthly_limit_cents: 100_00)
      create(:transaction, user: user, finance_category: snacks, amount_cents: 300_00, date: Date.new(2026, 7, 12))
      create(:transaction, user: user, finance_category: market, amount_cents: 200_00, date: Date.new(2026, 7, 13))
      create(:transaction, user: user, finance_category: market, amount_cents: 999_00, date: Date.new(2026, 7, 20))
      create(:budget)
    end

    it "lists the user's budgets in category order with their month-to-date status" do
      get api_v1_budgets_path, headers: auth

      expect(response).to have_http_status(:ok)
      expect(body).to include("currency" => "TRY", "subunit_to_unit" => 100, "as_of" => "2026-07-15")
      expect(body["budgets"].map { |b| b["category"]["name"] }).to eq([ "Market", "Ulaşım" ])
      expect(body["budgets"].first).to eq(
        "id" => market_budget.id, "finance_category_id" => market.id,
        "category" => { "id" => market.id, "name" => "Market", "color" => "#AA0000" },
        "color" => "#00FF00", "custom_color" => "#00FF00",
        "limit_cents" => 40_000, "spent_cents" => 50_000, "remaining_cents" => -10_000, "over_by_cents" => 10_000,
        "percent_used" => 125, "bar_percent" => 100, "pace_percent" => 48, "projected_cents" => 103_333, "state" => "over"
      )
    end

    it "lists the expense root categories that can still get a budget" do
      bills = create(:finance_category, user: user, name: "Faturalar", position: 1)
      create(:finance_category, user: user, name: "Maaş", kind: "income")

      get api_v1_budgets_path, headers: auth

      expect(body["budgetable_category_ids"]).to eq([ bills.id ])
    end
  end

  describe "POST /api/v1/budgets" do
    it "creates a budget and returns its status, colored like its category" do
      create(:transaction, user: user, finance_category: market, amount_cents: 400_00, date: Date.new(2026, 7, 2))

      post api_v1_budgets_path, params: { finance_category_id: market.id, monthly_limit_cents: 600_00 }, headers: auth, as: :json

      expect(response).to have_http_status(:created)
      # 400.00 spent by day 15 of 31 projects 826.66: over the 600.00 limit by month end.
      expect(body["budget"]).to include(
        "id" => user.budgets.last.id, "finance_category_id" => market.id, "color" => "#AA0000", "custom_color" => nil,
        "limit_cents" => 60_000, "spent_cents" => 40_000, "remaining_cents" => 20_000, "state" => "warning"
      )
    end

    it "refuses an income category, a subcategory and a limit of zero" do
      salary = create(:finance_category, user: user, kind: "income")
      snacks = create(:finance_category, user: user, parent: market)

      post api_v1_budgets_path, params: { finance_category_id: salary.id, monthly_limit_cents: 100 }, headers: auth, as: :json
      expect(body["details"]).to eq("finance_category_id" => [ { "error" => "must_be_expense" } ])
      post api_v1_budgets_path, params: { finance_category_id: snacks.id, monthly_limit_cents: 100 }, headers: auth, as: :json
      expect(body["details"]).to eq("finance_category_id" => [ { "error" => "must_be_root" } ])
      post api_v1_budgets_path, params: { finance_category_id: market.id, monthly_limit_cents: 0 }, headers: auth, as: :json
      expect(body["details"]).to eq("monthly_limit_cents" => [ { "error" => "greater_than", "value" => 0, "count" => 0 } ])
      expect(user.budgets.count).to eq(0)
    end

    it "refuses a second budget for the same category" do
      create(:budget, user: user, finance_category: market)

      post api_v1_budgets_path, params: { finance_category_id: market.id, monthly_limit_cents: 100 }, headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(body["details"]).to eq("finance_category_id" => [ { "error" => "taken", "value" => market.id } ])
    end

    it "turns a race past the uniqueness check into the same 422" do
      create(:budget, user: user, finance_category: market)
      uniqueness = Budget.validators_on(:finance_category_id).grep(ActiveRecord::Validations::UniquenessValidator).first
      allow(uniqueness).to receive(:validate_each)

      post api_v1_budgets_path, params: { finance_category_id: market.id, monthly_limit_cents: 100 }, headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      # The same detail as the validation's, value included.
      expect(body).to include("code" => "validation_failed",
        "details" => { "finance_category_id" => [ { "error" => "taken", "value" => market.id } ] })
      expect(user.budgets.count).to eq(1)
    end

    it "422s for a missing category, a malformed color and a limit that is not a whole number" do
      post api_v1_budgets_path, params: { monthly_limit_cents: 100, color: "blue" }, headers: auth, as: :json
      expect(body["details"].keys).to contain_exactly("finance_category", "color")

      post api_v1_budgets_path, params: { finance_category_id: market.id, monthly_limit_cents: "1,5" }, headers: auth, as: :json
      expect(body).to include("code" => "invalid_parameter", "param" => "monthly_limit_cents")
    end

    it "404s for another user's category" do
      post api_v1_budgets_path,
           params: { finance_category_id: create(:finance_category).id, monthly_limit_cents: 100 }, headers: auth, as: :json

      expect(response).to have_http_status(:not_found)
      expect(Budget.count).to eq(0)
    end
  end

  describe "PATCH /api/v1/budgets/:id" do
    it "rounds percent_used half up, as round(spent / limit × 100) says" do
      budget = create(:budget, user: user, finance_category: market, monthly_limit_cents: 300_00)
      create(:transaction, user: user, finance_category: market, amount_cents: 215_50, date: Date.new(2026, 7, 2))

      patch api_v1_budget_path(budget), params: { monthly_limit_cents: 100_00 }, headers: auth, as: :json

      expect(response).to have_http_status(:ok)
      expect(body["budget"]).to include(
        "limit_cents" => 100_00, "spent_cents" => 215_50, "over_by_cents" => 115_50,
        "percent_used" => 216, "bar_percent" => 100, "state" => "over"
      )
    end

    it "changes the limit and drops the custom color with null" do
      budget = create(:budget, user: user, finance_category: market, color: "#00FF00")

      patch api_v1_budget_path(budget), params: { monthly_limit_cents: 900_00, color: nil }, headers: auth, as: :json

      expect(response).to have_http_status(:ok)
      expect(body["budget"]).to include("limit_cents" => 90_000, "color" => "#AA0000", "custom_color" => nil)
      expect(budget.reload.color).to be_nil
    end

    it "moves the budget to a free category, not to one that has a budget" do
      budget = create(:budget, user: user, finance_category: market)
      bills = create(:finance_category, user: user)
      transport = create(:budget, user: user).finance_category

      patch api_v1_budget_path(budget), params: { finance_category_id: transport.id }, headers: auth, as: :json
      expect(body["details"]).to eq("finance_category_id" => [ { "error" => "taken", "value" => transport.id } ])

      patch api_v1_budget_path(budget), params: { finance_category_id: bills.id }, headers: auth, as: :json
      expect(response).to have_http_status(:ok)
      expect(budget.reload.finance_category_id).to eq(bills.id)
    end

    it "404s for another user's budget or category" do
      other = create(:budget, monthly_limit_cents: 100_00)
      mine = create(:budget, user: user, finance_category: market)

      patch api_v1_budget_path(other), params: { monthly_limit_cents: 1 }, headers: auth, as: :json
      expect(response).to have_http_status(:not_found)
      patch api_v1_budget_path(mine), params: { finance_category_id: other.finance_category_id }, headers: auth, as: :json
      expect(response).to have_http_status(:not_found)
      expect(other.reload.monthly_limit_cents).to eq(100_00)
    end
  end

  describe "DELETE /api/v1/budgets/:id" do
    it "deletes the budget and leaves its category's transactions alone" do
      budget = create(:budget, user: user, finance_category: market)
      transaction = create(:transaction, user: user, finance_category: market)

      delete api_v1_budget_path(budget), headers: auth

      expect(response).to have_http_status(:no_content)
      expect(Budget.exists?(budget.id)).to be(false)
      expect(transaction.reload.finance_category_id).to eq(market.id)
    end

    it "404s for another user's budget" do
      other = create(:budget)

      delete api_v1_budget_path(other), headers: auth

      expect(response).to have_http_status(:not_found)
      expect(Budget.exists?(other.id)).to be(true)
    end
  end
end
