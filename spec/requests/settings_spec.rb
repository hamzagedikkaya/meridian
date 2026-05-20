require 'rails_helper'

RSpec.describe "Settings", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /settings" do
    it "redirects to profile settings" do
      get settings_path
      expect(response).to redirect_to(profile_settings_path)
    end
  end

  describe "GET /settings/profile" do
    it "renders the profile tab" do
      get profile_settings_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Profile")
    end
  end

  describe "PATCH /settings/profile" do
    it "updates name and redirects" do
      patch profile_settings_path, params: { user: { name: "Renamed", email: user.email } }
      expect(response).to redirect_to(profile_settings_path)
      expect(user.reload.name).to eq("Renamed")
    end
  end

  describe "GET /settings/preferences" do
    it "renders the preferences tab" do
      get preferences_settings_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Preferences")
    end
  end

  describe "PATCH /settings/preferences" do
    it "updates all preference fields and redirects" do
      patch preferences_settings_path, params: { user: { timezone: "London", currency: "GBP", locale: "en", theme_preference: "light", weekly_review_day: 1 } }
      expect(response).to redirect_to(preferences_settings_path)
      expect(user.reload).to have_attributes(
        timezone: "London",
        currency: "GBP",
        locale: "en",
        theme_preference: "light",
        weekly_review_day: 1
      )
    end
  end

  describe "GET /settings/data" do
    it "renders the data tab" do
      get data_settings_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Backup")
    end
  end

  describe "GET /settings/notifications" do
    it "renders the notifications tab" do
      get notifications_settings_path
      expect(response).to have_http_status(:success)
    end
  end
end
