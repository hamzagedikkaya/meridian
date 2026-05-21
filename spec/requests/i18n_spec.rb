require 'rails_helper'

# Verifies the locale story: a user's `locale` attribute drives the UI language
# across views via ApplicationController#set_locale + the t() helper.
RSpec.describe "I18n", type: :request do
  describe "with a Turkish-locale user" do
    let(:user) { create(:user, locale: "tr") }

    before { sign_in user }

    it "renders the sidebar nav in Turkish" do
      get root_path
      expect(response.body).to include("Pano")
      expect(response.body).to include("Finans")
      expect(response.body).to include("Görevler")
    end

    it "renders the finance dashboard in Turkish" do
      get finance_root_path
      expect(response.body).to include("Bu ay net")
      expect(response.body).to include("Gelir")
    end

    it "renders settings tabs in Turkish" do
      get profile_settings_path
      expect(response.body).to include("Profil")
      expect(response.body).to include("Tercihler")
    end

    it "sets html lang to tr" do
      get root_path
      expect(response.body).to include('lang="tr"')
    end
  end

  describe "with an English-locale user" do
    let(:user) { create(:user, locale: "en") }

    before { sign_in user }

    it "renders the sidebar nav in English" do
      get root_path
      expect(response.body).to include("Dashboard")
      expect(response.body).to include("Finance")
      expect(response.body).to include("Todos")
    end

    it "sets html lang to en" do
      get root_path
      expect(response.body).to include('lang="en"')
    end
  end
end
