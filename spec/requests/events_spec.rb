require 'rails_helper'

RSpec.describe "Events", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /events/new" do
    it "renders the modal partial wrapped in turbo-frame" do
      get new_event_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include('turbo-frame id="modal"')
    end

    it "uses the provided date for default start_at" do
      get new_event_path(date: "2026-07-04")
      expect(response.body).to include("2026-07-04")
    end
  end

  describe "POST /events" do
    it "creates an event and redirects to the calendar" do
      params = { event: { title: "Lunch", start_at: 1.hour.from_now.iso8601, event_type: "personal" } }
      expect { post events_path, params: params }
        .to change(Event, :count).by(1)
      expect(response).to redirect_to(calendar_path)
    end
  end

  describe "PATCH /events/:id/move" do
    let(:event) { create(:event, user: user, start_at: Time.zone.local(2026, 5, 10, 14, 30), end_at: Time.zone.local(2026, 5, 10, 15, 30)) }

    it "moves the event to a new date while preserving time of day" do
      patch move_event_path(event), params: { date: "2026-05-15" }, as: :json
      expect(response).to have_http_status(:success)
      event.reload
      expect(event.start_at.to_date).to eq(Date.new(2026, 5, 15))
      expect(event.start_at.hour).to eq(14)
      expect(event.start_at.min).to eq(30)
      expect(event.end_at.to_date).to eq(Date.new(2026, 5, 15))
    end

    it "rejects an invalid date string" do
      patch move_event_path(event), params: { date: "not-a-date" }, as: :json
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "PATCH /events/:id/reschedule" do
    let(:event) { create(:event, user: user, start_at: Time.zone.local(2026, 5, 10, 9), end_at: Time.zone.local(2026, 5, 10, 10)) }

    it "updates start and end times" do
      patch reschedule_event_path(event), params: { start_at: "2026-05-10T15:00", end_at: "2026-05-10T16:00" }, as: :json
      expect(response).to have_http_status(:success)
      event.reload
      expect(event.start_at.hour).to eq(15)
      expect(event.end_at.hour).to eq(16)
    end
  end

  describe "DELETE /events/:id" do
    let!(:event) { create(:event, user: user) }

    it "destroys the event and redirects" do
      expect { delete event_path(event) }.to change(Event, :count).by(-1)
    end
  end
end
