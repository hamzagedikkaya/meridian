require "rails_helper"

RSpec.describe "Api::V1::FinanceCategories", type: :request do
  let(:user) { create(:user) }
  let(:auth) { { "Authorization" => "Bearer #{user.api_token}" } }

  it "returns JSON 401 without a token" do
    get api_v1_finance_categories_path

    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)["error"]).to eq("unauthorized")
  end

  it "returns all of the current user's categories ordered by position then name" do
    salary = create(:finance_category, user: user, name: "Maaş", kind: "income", position: 0)
    market = create(:finance_category, user: user, name: "Market", position: 1, color: "#AA0000")
    transport = create(:finance_category, user: user, name: "Ulaşım", position: 2)
    snacks = create(:finance_category, user: user, name: "Atıştırmalık", parent: market, position: 3)
    create(:finance_category, name: "Someone else's")

    get api_v1_finance_categories_path, headers: auth

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["categories"].map { |c| c["name"] }).to eq([ "Maaş", "Market", "Ulaşım", "Atıştırmalık" ])
    expect(body["categories"][1]).to eq(
      "id" => market.id, "name" => "Market", "kind" => "expense",
      "color" => "#AA0000", "parent_id" => nil, "position" => 1
    )
    expect(body["categories"].last).to include("id" => snacks.id, "parent_id" => market.id)
    expect(body["categories"].first).to include("id" => salary.id, "kind" => "income")
    expect(body["categories"][2]).to include("id" => transport.id)
  end
end
