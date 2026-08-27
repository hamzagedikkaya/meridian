require "rails_helper"

RSpec.describe "Api::V1::Me", type: :request do
  let(:user) { create(:user, locale: "tr", theme_preference: "dark") }
  let(:auth) { { "Authorization" => "Bearer #{user.api_token}" } }

  describe "GET /api/v1/me" do
    it "returns JSON 401 without a token" do
      get api_v1_me_path

      expect(response).to have_http_status(:unauthorized)
      expect(response.media_type).to eq("application/json")
      expect(JSON.parse(response.body)["error"]).to eq("unauthorized")
    end

    it "returns the profile the mobile client renders" do
      get api_v1_me_path, headers: auth

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["user"]).to include(
        "id" => user.id,
        "email" => user.email,
        "display_name" => user.display_name,
        "initials" => user.initials,
        "currency" => user.currency,
        "locale" => "tr",
        "theme_preference" => "dark"
      )
    end
  end

  describe "PATCH /api/v1/me" do
    it "persists the language and theme chosen on the phone" do
      patch api_v1_me_path, params: { locale: "en", theme_preference: "light" }, headers: auth

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["user"]).to include(
        "locale" => "en",
        "theme_preference" => "light"
      )
      expect(user.reload.locale).to eq("en")
      expect(user.theme_preference).to eq("light")
    end

    it "accepts a partial update" do
      patch api_v1_me_path, params: { locale: "en" }, headers: auth

      expect(response).to have_http_status(:ok)
      expect(user.reload.locale).to eq("en")
      expect(user.theme_preference).to eq("dark")
    end

    it "ignores fields the client may not change" do
      patch api_v1_me_path, params: { locale: "en", email: "hijack@example.com", currency: "USD" }, headers: auth

      expect(response).to have_http_status(:ok)
      expect(user.reload.email).not_to eq("hijack@example.com")
      expect(user.currency).not_to eq("USD")
    end

    it "422s with field errors on an unsupported locale" do
      patch api_v1_me_path, params: { locale: "de" }, headers: auth

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["errors"]).to have_key("locale")
      expect(user.reload.locale).to eq("tr")
    end

    it "401s without a token" do
      patch api_v1_me_path, params: { locale: "en" }

      expect(response).to have_http_status(:unauthorized)
      expect(user.reload.locale).to eq("tr")
    end
  end
end
