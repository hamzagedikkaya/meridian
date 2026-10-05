require "rails_helper"

# The login limits (Api::V1::SessionsController, Users::SessionsController)
# and the token rotation that every password change triggers.
RSpec.describe "Login limits and token rotation", type: :request do
  let(:user) { create(:user, password: "password123", password_confirmation: "password123") }

  def body = JSON.parse(response.body)
  def lan(address) = { "REMOTE_ADDR" => address }

  describe "POST /api/v1/session" do
    it "keeps counting a LAN peer that sends a new X-Forwarded-For on every request" do
      10.times do |i|
        post api_v1_session_path, params: { email: "nobody#{i}@example.com", password: "x" },
             headers: { "X-Forwarded-For" => "203.0.113.#{i}" }, env: lan("192.168.1.50")
      end

      post api_v1_session_path, params: { email: user.email, password: "password123" },
           headers: { "X-Forwarded-For" => "203.0.113.99" }, env: lan("192.168.1.50")

      expect(response).to have_http_status(:too_many_requests)
    end

    it "counts each client of a proxy on this machine by the address the proxy appended" do
      10.times do |i|
        post api_v1_session_path, params: { email: "nobody#{i}@example.com", password: "x" },
             headers: { "X-Forwarded-For" => "198.51.100.41" }
      end

      post api_v1_session_path, params: { email: "other@example.com", password: "x" },
           headers: { "X-Forwarded-For" => "203.0.113.7, 198.51.100.41" }
      expect(response).to have_http_status(:too_many_requests)

      post api_v1_session_path, params: { email: user.email, password: "password123" },
           headers: { "X-Forwarded-For" => "198.51.100.42" }
      expect(response).to have_http_status(:ok)
    end

    it "limits guesses at one email from many addresses" do
      10.times do |i|
        post api_v1_session_path, params: { email: user.email, password: "wrong" }, env: lan("192.168.1.#{i + 10}")
      end

      post api_v1_session_path, params: { email: " #{user.email.upcase} ", password: "password123" }, env: lan("192.168.1.99")

      expect(response).to have_http_status(:too_many_requests)
      expect(body).to eq("error" => "too_many_requests", "code" => "too_many_requests")
    end

    it "compares a password even when no user has the email, so the timing does not tell" do
      allow(Devise::Encryptor).to receive(:compare).and_call_original

      post api_v1_session_path, params: { email: "nobody@example.com", password: "password123" }

      expect(response).to have_http_status(:unauthorized)
      expect(Devise::Encryptor).to have_received(:compare).once
    end
  end

  describe "POST /users/sign_in (web)" do
    it "refuses an 11th attempt from one address within 5 minutes" do
      10.times do |i|
        post user_session_path, params: { user: { email: "nobody#{i}@example.com", password: "x" } }
      end

      post user_session_path, params: { user: { email: user.email, password: "password123" } }

      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:alert]).to eq(I18n.t("devise.failure.too_many_attempts"))
      get "/"
      expect(response).to redirect_to(new_user_session_path)
    end

    it "limits guesses at one email from many addresses" do
      10.times do |i|
        post user_session_path, params: { user: { email: user.email, password: "wrong" } }, env: lan("10.0.0.#{i + 2}")
      end

      post user_session_path, params: { user: { email: user.email, password: "password123" } }, env: lan("10.0.0.99")

      expect(flash[:alert]).to eq(I18n.t("devise.failure.too_many_attempts"))
    end

    it "still signs in below the limit" do
      post user_session_path, params: { user: { email: user.email, password: "password123" } }

      get "/"
      expect(response).to have_http_status(:success)
    end
  end

  describe "a password change on the web replaces the API token" do
    it "through the profile page" do
      old_token = user.api_token
      sign_in user

      patch "/settings/profile", params: { user: { password: "newpass456", password_confirmation: "newpass456" } }

      expect(response).to have_http_status(:redirect)
      expect(user.reload.valid_password?("newpass456")).to be(true)
      expect(user.api_token).to be_present
      expect(user.api_token).not_to eq(old_token)
      get api_v1_me_path, headers: { "Authorization" => "Bearer #{old_token}" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "through a Devise password reset link" do
      old_token = user.api_token
      reset_token = user.send_reset_password_instructions

      put user_password_path, params: { user: { reset_password_token: reset_token, password: "newpass456", password_confirmation: "newpass456" } }

      expect(user.reload.valid_password?("newpass456")).to be(true)
      expect(user.api_token).not_to eq(old_token)
      get api_v1_me_path, headers: { "Authorization" => "Bearer #{old_token}" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "but a profile change without a new password keeps the token" do
      old_token = user.api_token
      sign_in user

      patch "/settings/profile", params: { user: { name: "Yeni Ad", password: "", password_confirmation: "" } }

      expect(user.reload.name).to eq("Yeni Ad")
      expect(user.api_token).to eq(old_token)
    end
  end
end
