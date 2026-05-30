require 'rails_helper'

RSpec.describe "Pages", type: :request do
  describe "GET /" do
    let(:user) { create(:user) }

    before { sign_in user }

    it "returns http success and renders the welcome shell" do
      get "/"
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Meridian")
    end

    it "does not render the perfect-day widget on home (it lives on /habits now)" do
      habit = create(:habit, user: user, created_at: 5.days.ago)
      habit.habit_logs.create!(date: 1.day.ago.to_date, completed: true)
      get "/"
      expect(response.body).not_to include(I18n.t("pages.home.perfect_days"))
    end
  end
end
