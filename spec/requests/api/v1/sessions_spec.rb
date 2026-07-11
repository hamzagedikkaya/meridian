require "rails_helper"

RSpec.describe "Api::V1::Sessions", type: :request do
  let(:user) { create(:user, password: "password123", password_confirmation: "password123") }

  it "returns a bearer token for valid credentials" do
    post api_v1_session_path, params: { email: user.email, password: "password123" }

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["token"]).to eq(user.api_token)
    expect(body.dig("user", "email")).to eq(user.email)
  end

  it "401s on a wrong password" do
    post api_v1_session_path, params: { email: user.email, password: "wrong" }

    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)["error"]).to eq("invalid_credentials")
  end
end
