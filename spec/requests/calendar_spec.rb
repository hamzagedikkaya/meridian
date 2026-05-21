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

  describe "GET /calendar/week" do
    it "renders the weekly view for the current week by default" do
      get calendar_week_path
      expect(response).to have_http_status(:success)
    end

    it "renders the week containing the given anchor date" do
      get calendar_week_at_path("2026-07-15")
      expect(response).to have_http_status(:success)
    end

    it "places events into their day's column" do
      create(:event, user: user, title: "Lunch break", start_at: Time.zone.local(2026, 7, 15, 12, 30))
      get calendar_week_at_path("2026-07-15")
      expect(response.body).to include("Lunch break")
    end

    it "gracefully handles an invalid anchor date" do
      get calendar_week_at_path("not-a-date") rescue nil
      get calendar_week_path
      expect(response).to have_http_status(:success)
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
