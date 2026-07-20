require "rails_helper"

RSpec.describe "Api::V1::Events", type: :request do
  let(:user) { create(:user) }
  let(:auth) { { "Authorization" => "Bearer #{user.api_token}" } }

  it "401s without a token" do
    get api_v1_events_path

    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)["error"]).to eq("unauthorized")
  end

  describe "GET /api/v1/events" do
    it "defaults to today..today+30 and hides other users' events" do
      start_at = Date.current.in_time_zone.change(hour: 14)
      event = create(:event, user: user, title: "Dentist", start_at: start_at, end_at: start_at + 30.minutes,
                     location: "Kadıköy", event_type: "health")
      create(:event, user: user, title: "Too far", start_at: 40.days.from_now)
      create(:event, user: user, title: "Past", start_at: 2.days.ago)
      create(:event, title: "Someone else's", start_at: 1.day.from_now)

      get api_v1_events_path, headers: auth

      expect(response).to have_http_status(:ok)
      events = JSON.parse(response.body)["events"]
      expect(events.map { |e| e["title"] }).to eq([ "Dentist" ])
      expect(events.first).to include(
        "id" => event.id, "all_day" => false, "event_type" => "health",
        "location" => "Kadıköy", "duration_minutes" => 30,
        "occurrences" => [ Date.current.iso8601 ]
      )
    end

    it "honors explicit from/to bounds" do
      create(:event, user: user, title: "In window", start_at: 10.days.from_now.change(hour: 9))
      create(:event, user: user, title: "Outside", start_at: 20.days.from_now)

      get api_v1_events_path(from: 9.days.from_now.to_date.iso8601, to: 11.days.from_now.to_date.iso8601),
          headers: auth

      expect(JSON.parse(response.body)["events"].map { |e| e["title"] }).to eq([ "In window" ])
    end

    it "expands recurring events that started before the range" do
      create(:event, user: user, title: "Weekly standup", recurring: true, recurrence_rule: "FREQ=WEEKLY",
             start_at: 21.days.ago.change(hour: 9))

      get api_v1_events_path(from: Date.current.iso8601, to: 13.days.from_now.to_date.iso8601), headers: auth

      events = JSON.parse(response.body)["events"]
      expect(events.map { |e| e["title"] }).to eq([ "Weekly standup" ])
      expect(events.first["occurrences"]).to eq([ Date.current.iso8601, 7.days.from_now.to_date.iso8601 ])
    end

    it "omits non-recurring events outside the range even when recurring ones match" do
      create(:event, user: user, title: "Old one-off", start_at: 21.days.ago)

      get api_v1_events_path, headers: auth

      expect(JSON.parse(response.body)["events"]).to be_empty
    end
  end
end
