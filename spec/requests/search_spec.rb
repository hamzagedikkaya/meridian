require 'rails_helper'

RSpec.describe "Search", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it "returns matching transactions" do
    create(:transaction, user: user, description: "Netflix subscription")
    get search_path, params: { q: "netflix" }, headers: { "Accept" => "application/json" }
    expect(response).to have_http_status(:success)
    body = JSON.parse(response.body)
    expect(body["results"].map { |r| r["type"] }).to include("Transaction")
  end

  it "returns empty for blank query" do
    get search_path, params: { q: "" }, headers: { "Accept" => "application/json" }
    body = JSON.parse(response.body)
    expect(body["results"]).to eq([])
  end
end
