require "rails_helper"

RSpec.describe "Api::V1::Sessions", type: :request do
  let(:user) { create(:user, password: "password123", password_confirmation: "password123") }

  def body = JSON.parse(response.body)
  def auth_for(token) = { "Authorization" => "Bearer #{token}" }

  # The login limit is per IP, and every request spec comes from 127.0.0.1.
  before { Api::V1::SessionsController::RATE_LIMIT_STORE.clear }

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
    expect(JSON.parse(response.body)).to eq("error" => "invalid_credentials", "code" => "invalid_credentials")
  end

  it "429s after 10 sign-in attempts in 5 minutes from one address" do
    10.times { post api_v1_session_path, params: { email: user.email, password: "wrong" } }

    post api_v1_session_path, params: { email: user.email, password: "password123" }

    expect(response).to have_http_status(:too_many_requests)
    expect(body).to eq("error" => "too_many_requests", "code" => "too_many_requests")
  end

  describe "DELETE /api/v1/session" do
    it "revokes the caller's token" do
      old_token = user.api_token

      delete api_v1_session_path, headers: auth_for(old_token)

      expect(response).to have_http_status(:no_content)
      expect(response.body).to be_empty
      expect(user.reload.api_token).to be_present
      expect(user.api_token).not_to eq(old_token)

      get api_v1_me_path, headers: auth_for(old_token)
      expect(response).to have_http_status(:unauthorized)
    end

    it "lets the next sign-in return the new token" do
      delete api_v1_session_path, headers: auth_for(user.api_token)

      post api_v1_session_path, params: { email: user.email, password: "password123" }

      expect(response).to have_http_status(:ok)
      expect(body["token"]).to eq(user.reload.api_token)
      get api_v1_me_path, headers: auth_for(body["token"])
      expect(response).to have_http_status(:ok)
    end

    it "leaves other users signed in" do
      other = create(:user)
      other_token = other.api_token

      delete api_v1_session_path, headers: auth_for(user.api_token)

      expect(other.reload.api_token).to eq(other_token)
      get api_v1_me_path, headers: auth_for(other_token)
      expect(response).to have_http_status(:ok)
    end

    it "signs out a user whose stored record fails a newer validation" do
      user.update_column(:name, nil)
      old_token = user.api_token

      delete api_v1_session_path, headers: auth_for(old_token)

      expect(response).to have_http_status(:no_content)
      expect(user.reload.api_token).not_to eq(old_token)
    end

    it "401s without a token, or with one that was already revoked" do
      token = user.api_token

      delete api_v1_session_path

      expect(response).to have_http_status(:unauthorized)
      expect(body).to eq("error" => "unauthorized", "code" => "unauthorized")
      expect(user.reload.api_token).to eq(token)

      delete api_v1_session_path, headers: auth_for(token)
      delete api_v1_session_path, headers: auth_for(token)

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
