require 'rails_helper'

RSpec.describe "Events", type: :request do
  include ActiveSupport::Testing::TimeHelpers

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

    it "prefills the title and time quick capture sends" do
      get new_event_path(date: "2026-07-04", time: "15:30", event: { title: "Dişçi" })

      expect(response.body).to include('value="Dişçi"')
      expect(response.body).to include('value="2026-07-04T15:30:00"')
    end

    it "falls back to 09:00 for a malformed time and to the next hour for a malformed date" do
      get new_event_path(date: "2026-07-04", time: "25:99")
      expect(response.body).to include('value="2026-07-04T09:00:00"')

      travel_to Time.zone.local(2026, 7, 4, 10, 30) do
        get new_event_path(date: "not-a-date")
      end
      expect(response).to have_http_status(:success)
      expect(response.body).to include('value="2026-07-04T11:00:00"')
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

  # One row is the whole series, so a dragged occurrence must not re-anchor
  # it on the drop day (that dropped every earlier occurrence).
  describe "dragging an occurrence of a series" do
    let!(:series) do
      create(:event, user: user, title: "Weekly yoga", start_at: Time.zone.local(2026, 10, 6, 18),
                     end_at: Time.zone.local(2026, 10, 6, 19), recurring: true, recurrence_rule: "FREQ=WEEKLY;BYDAY=TU")
    end

    it "refuses a reschedule with a JSON error and keeps the series' anchor" do
      patch reschedule_event_path(series), params: { start_at: "2026-11-10T19:00", end_at: "2026-11-10T20:00" }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq("ok" => false, "error" => I18n.t("events.series_not_draggable"))
      expect(series.reload.start_at).to eq(Time.zone.local(2026, 10, 6, 18))
      expect(series.occurrences_between(Date.new(2026, 10, 1), Date.new(2026, 10, 31)).size).to eq(4)
    end

    it "refuses a move with a JSON error" do
      patch move_event_path(series), params: { date: "2026-11-12" }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["ok"]).to be(false)
      expect(series.reload.start_at).to eq(Time.zone.local(2026, 10, 6, 18))
    end

    it "redirects an HTML request back to the calendar with the message" do
      patch reschedule_event_path(series), params: { start_at: "2026-11-10T19:00" }

      expect(response).to redirect_to(calendar_path)
      expect(flash[:alert]).to eq(I18n.t("events.series_not_draggable"))
      expect(series.reload.start_at).to eq(Time.zone.local(2026, 10, 6, 18))
    end

    describe "the calendar tiles" do
      let!(:one_off) { create(:event, user: user, title: "Dentist", start_at: Time.zone.local(2026, 11, 11, 10)) }

      it "draws a series' week tiles without drag handles, a one-off's with them" do
        get calendar_week_at_path("2026-11-09")
        week = Nokogiri::HTML(response.body)
        tiles = week.css(%([data-event-id="#{series.id}"]))

        expect(tiles.map { |tile| tile["draggable"] }).to eq([ nil ])
        expect(tiles.first["data-action"]).to eq("click->calendar-week#openEvent")
        expect(week.css(%([data-event-id="#{one_off.id}"][draggable="true"])).size).to eq(1)
      end

      it "draws a series' month links undraggable, a one-off's draggable" do
        get calendar_month_path(2026, 11)
        month = Nokogiri::HTML(response.body)
        series_links = month.css(%(a[href="#{edit_event_path(series)}"]))

        expect(series_links.size).to be >= 4
        expect(series_links.map { |link| [ link["draggable"], link["data-action"] ] }.uniq).to eq([ [ "false", nil ] ])
        expect(month.css(%(a[href="#{edit_event_path(one_off)}"][draggable="true"])).size).to eq(1)
      end
    end
  end

  describe "DELETE /events/:id" do
    let!(:event) { create(:event, user: user) }

    it "destroys the event and redirects" do
      expect { delete event_path(event) }.to change(Event, :count).by(-1)
    end
  end
end
