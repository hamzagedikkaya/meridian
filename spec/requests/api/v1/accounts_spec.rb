require "rails_helper"

RSpec.describe "Api::V1::Accounts", type: :request do
  let(:user) { create(:user) }
  let(:auth) { { "Authorization" => "Bearer #{user.api_token}" } }

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

  it "returns only the current user's active accounts, with balances" do
    create(:account, user: user, name: "Cash", currency: "TRY", initial_balance_cents: 1_000_00)
    create(:account, user: user, name: "Archived", archived_at: Time.current)
    create(:account, name: "Someone else's")

    get api_v1_accounts_path, headers: auth

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["accounts"].map { |a| a["name"] }).to eq([ "Cash" ])
    expect(body["accounts"].first).to include(
      "currency" => "TRY", "subunit_to_unit" => 100, "balance_cents" => 1_000_00, "archived" => false
    )
  end
end
