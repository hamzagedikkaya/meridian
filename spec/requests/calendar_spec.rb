require 'rails_helper'

RSpec.describe "Calendar", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /calendar" do
    it "renders the current month" do
      get calendar_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include(Date.current.strftime("%B"))
    end
  end

  describe "GET /calendar/:year/:month" do
    it "renders the specified month" do
      get calendar_month_path(2026, 3)
      expect(response).to have_http_status(:success)
      expect(response.body).to include("March 2026")
    end
  end

  describe "GET /calendar.ics" do
    it "returns iCal feed" do
      create(:event, user: user, title: "My event")
      get calendar_feed_path
      expect(response).to have_http_status(:success)
      expect(response.content_type).to start_with("text/calendar")
      expect(response.body).to include("BEGIN:VCALENDAR")
      expect(response.body).to include("My event")
    end
  end
end
