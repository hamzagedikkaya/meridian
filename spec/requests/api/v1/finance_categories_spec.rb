require "rails_helper"

RSpec.describe "Api::V1::FinanceCategories", type: :request do
  let(:user) { create(:user) }
  let(:auth) { { "Authorization" => "Bearer #{user.api_token}" } }

  it "returns JSON 401 without a token" do
    get api_v1_finance_categories_path

    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)["error"]).to eq("unauthorized")
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
end
