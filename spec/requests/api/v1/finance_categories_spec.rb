require "rails_helper"

RSpec.describe "Api::V1::FinanceCategories", type: :request do
  let(:user) { create(:user) }
  let(:auth) { { "Authorization" => "Bearer #{user.api_token}" } }

  def body = JSON.parse(response.body)

  it "returns JSON 401 without a token" do
    get api_v1_finance_categories_path

    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)["error"]).to eq("unauthorized")
  end

  it "401s on every write and on show without a token" do
    category = create(:finance_category, user: user)

    get api_v1_finance_category_path(category)
    expect(response).to have_http_status(:unauthorized)
    post api_v1_finance_categories_path, params: { name: "Market" }, as: :json
    expect(response).to have_http_status(:unauthorized)
    patch api_v1_finance_category_path(category), params: { name: "X" }, as: :json
    expect(response).to have_http_status(:unauthorized)
    delete api_v1_finance_category_path(category)
    expect(response).to have_http_status(:unauthorized)
  end

  context "with the current user's categories" do
    let!(:salary) { create(:finance_category, user: user, name: "Maaş", kind: "income", position: 0) }
    let!(:market) { create(:finance_category, user: user, name: "Market", position: 1, color: "#AA0000") }
    let!(:snacks) { create(:finance_category, user: user, name: "Atıştırmalık", parent: market, position: 3) }

    before do
      create(:finance_category, user: user, name: "Ulaşım", position: 2)
      create(:finance_category, name: "Someone else's")
      get api_v1_finance_categories_path, headers: auth
    end

    it "returns them ordered by position then name, excluding other users'" do
      expect(response).to have_http_status(:ok)
      names = JSON.parse(response.body)["categories"].map { |c| c["name"] }
      expect(names).to eq([ "Maaş", "Market", "Ulaşım", "Atıştırmalık" ])
    end

    it "serializes each category's fields" do
      categories = JSON.parse(response.body)["categories"]
      expect(categories[1]).to eq(
        "id" => market.id, "name" => "Market", "kind" => "expense",
        "color" => "#AA0000", "parent_id" => nil, "position" => 1
      )
      expect(categories.first).to include("id" => salary.id, "kind" => "income")
      expect(categories.last).to include("id" => snacks.id, "parent_id" => market.id)
    end
  end

  describe "GET /api/v1/finance_categories/:id" do
    it "counts what a delete would touch across the category and its subcategories" do
      market = create(:finance_category, user: user, name: "Market")
      snacks = create(:finance_category, user: user, parent: market)
      create(:transaction, user: user, finance_category: market)
      create_list(:transaction, 2, user: user, finance_category: snacks)
      create(:subscription, user: user, finance_category: snacks)
      budget = create(:budget, user: user, finance_category: market)

      get api_v1_finance_category_path(market), headers: auth

      expect(body["category"]).to include(
        "id" => market.id, "name" => "Market", "children_count" => 1, "transactions_count" => 3,
        "subscriptions_count" => 1, "budgets_count" => 1, "budget_id" => budget.id, "kind_editable" => false
      )
    end

    it "lets the kind of an unused category change" do
      category = create(:finance_category, user: user)

      get api_v1_finance_category_path(category), headers: auth

      expect(body["category"]).to include("children_count" => 0, "transactions_count" => 0, "budget_id" => nil, "kind_editable" => true)
    end

    it "404s for another user's category" do
      get api_v1_finance_category_path(create(:finance_category)), headers: auth

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/finance_categories" do
    it "creates a root category, expense by default" do
      post api_v1_finance_categories_path, params: { name: "Kira", color: "#225588", position: 4 }, headers: auth, as: :json

      expect(response).to have_http_status(:created)
      expect(body["category"]).to include(
        "name" => "Kira", "kind" => "expense", "color" => "#225588", "parent_id" => nil, "position" => 4
      )
    end

    it "creates a subcategory that takes its parent's kind" do
      salary = create(:finance_category, user: user, name: "Maaş", kind: "income")

      post api_v1_finance_categories_path, params: { name: "Prim", parent_id: salary.id }, headers: auth, as: :json

      expect(response).to have_http_status(:created)
      expect(body["category"]).to include("kind" => "income", "parent_id" => salary.id)
    end

    it "refuses a name the user already has under the same parent, ignoring case" do
      create(:finance_category, user: user, name: "Diğer", kind: "income")

      post api_v1_finance_categories_path, params: { name: "diğer", kind: "expense" }, headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(body).to include("code" => "validation_failed", "details" => { "name" => [ { "error" => "taken", "value" => "diğer" } ] })
    end

    it "refuses a parent of the other kind and a parent that is itself a subcategory" do
      market = create(:finance_category, user: user, name: "Market")
      snacks = create(:finance_category, user: user, parent: market)
      salary = create(:finance_category, user: user, kind: "income")

      post api_v1_finance_categories_path, params: { name: "A", kind: "expense", parent_id: salary.id }, headers: auth, as: :json
      expect(body["details"]).to eq("parent_id" => [ { "error" => "must_match_kind" } ])

      post api_v1_finance_categories_path, params: { name: "B", parent_id: snacks.id }, headers: auth, as: :json
      expect(body["details"]).to eq("parent_id" => [ { "error" => "must_be_root" } ])
    end

    it "422s for an unknown kind, a blank name and a malformed color" do
      post api_v1_finance_categories_path, params: { name: "", kind: "savings", color: "#12" }, headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(body["details"].keys).to contain_exactly("name", "kind", "color")
    end

    it "422s invalid_parameter for a position that is not a whole number" do
      post api_v1_finance_categories_path, params: { name: "Kira", position: nil }, headers: auth, as: :json

      expect(body).to include("code" => "invalid_parameter", "param" => "position")
    end

    it "404s for another user's parent" do
      post api_v1_finance_categories_path,
           params: { name: "Sneaky", parent_id: create(:finance_category).id }, headers: auth, as: :json

      expect(response).to have_http_status(:not_found)
      expect(user.finance_categories.count).to eq(0)
    end
  end

  describe "PATCH /api/v1/finance_categories/:id" do
    it "renames, recolors, reorders and moves a category" do
      market = create(:finance_category, user: user, name: "Market")
      food = create(:finance_category, user: user, name: "Gıda", color: "#111111")

      patch api_v1_finance_category_path(food),
            params: { name: "Yemek", position: 7, parent_id: market.id }, headers: auth, as: :json

      expect(response).to have_http_status(:ok)
      expect(body["category"]).to include("name" => "Yemek", "color" => "#111111", "position" => 7, "parent_id" => market.id)
    end

    it "promotes a subcategory to a root with parent_id null" do
      market = create(:finance_category, user: user)
      snacks = create(:finance_category, user: user, parent: market)

      patch api_v1_finance_category_path(snacks), params: { parent_id: nil }, headers: auth, as: :json

      expect(response).to have_http_status(:ok)
      expect(snacks.reload.parent_id).to be_nil
    end

    it "refuses to move a category that has subcategories" do
      market = create(:finance_category, user: user)
      create(:finance_category, user: user, parent: market)
      bills = create(:finance_category, user: user)

      patch api_v1_finance_category_path(market), params: { parent_id: bills.id }, headers: auth, as: :json

      expect(body["details"]).to eq("parent_id" => [ { "error" => "cannot_have_children" } ])
      expect(market.reload.parent_id).to be_nil
    end

    it "refuses to move a budgeted category under a parent" do
      market = create(:finance_category, user: user)
      bills = create(:finance_category, user: user)
      create(:budget, user: user, finance_category: market)

      patch api_v1_finance_category_path(market), params: { parent_id: bills.id }, headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(body["details"]).to eq("parent_id" => [ { "error" => "has_budget" } ])
    end

    it "changes the kind of a category nothing uses" do
      category = create(:finance_category, user: user)

      patch api_v1_finance_category_path(category), params: { kind: "income" }, headers: auth, as: :json

      expect(response).to have_http_status(:ok)
      expect(category.reload.kind).to eq("income")
    end

    it "refuses a kind change while transactions, subcategories, budgets or subscriptions use it" do
      used = {
        transaction: create(:transaction, user: user).finance_category,
        child: create(:finance_category, user: user, parent: create(:finance_category, user: user)).parent,
        budget: create(:budget, user: user).finance_category,
        subscription: create(:subscription, user: user, finance_category: create(:finance_category, user: user)).finance_category
      }

      used.each_value do |category|
        patch api_v1_finance_category_path(category), params: { kind: "income" }, headers: auth, as: :json
        expect(body).to include("code" => "kind_locked", "errors" => { "kind" => [ I18n.t("api.errors.kind_locked") ] })
      end
      expect(FinanceCategory.where(id: used.values.map(&:id)).pluck(:kind)).to all(eq("expense"))
    end

    it "404s for another user's category or parent" do
      other = create(:finance_category, name: "Theirs")
      mine = create(:finance_category, user: user)

      patch api_v1_finance_category_path(other), params: { name: "Mine" }, headers: auth, as: :json
      expect(response).to have_http_status(:not_found)
      patch api_v1_finance_category_path(mine), params: { parent_id: other.id }, headers: auth, as: :json
      expect(response).to have_http_status(:not_found)
      expect(mine.reload.parent_id).to be_nil
    end
  end

  describe "DELETE /api/v1/finance_categories/:id" do
    it "deletes subcategories and budgets; transactions and subscriptions lose the category" do
      market = create(:finance_category, user: user)
      snacks = create(:finance_category, user: user, parent: market)
      transactions = [ create(:transaction, user: user, finance_category: market), create(:transaction, user: user, finance_category: snacks) ]
      subscription = create(:subscription, user: user, finance_category: snacks)
      create(:budget, user: user, finance_category: market)

      delete api_v1_finance_category_path(market), headers: auth

      expect(response).to have_http_status(:no_content)
      expect(FinanceCategory.where(id: [ market.id, snacks.id ])).to be_empty
      expect(user.budgets).to be_empty
      expect(Transaction.where(id: transactions.map(&:id)).pluck(:finance_category_id)).to eq([ nil, nil ])
      expect(subscription.reload.finance_category_id).to be_nil
    end

    it "404s for another user's category" do
      other = create(:finance_category)

      delete api_v1_finance_category_path(other), headers: auth

      expect(response).to have_http_status(:not_found)
      expect(FinanceCategory.exists?(other.id)).to be(true)
    end
  end
end
