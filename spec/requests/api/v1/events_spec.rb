require "rails_helper"

RSpec.describe "Api::V1::Events", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:auth) { { "Authorization" => "Bearer #{user.api_token}" } }

  def body = JSON.parse(response.body)

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

    it "includes a recurring event's occurrence on the last day of the window, even when from == to" do
      create(:event, user: user, title: "Daily", recurring: true, recurrence_rule: "FREQ=DAILY",
                     start_at: 3.days.ago.change(hour: 9))

      get api_v1_events_path(from: Date.current.iso8601, to: Date.current.iso8601), headers: auth

      expect(JSON.parse(response.body)["events"].map { |e| e["occurrences"] }).to eq([ [ Date.current.iso8601 ] ])
    end

    it "omits non-recurring events outside the range even when recurring ones match" do
      create(:event, user: user, title: "Old one-off", start_at: 21.days.ago)

      get api_v1_events_path, headers: auth

      expect(JSON.parse(response.body)["events"]).to be_empty
    end

    it "says which events are recurring series" do
      create(:event, user: user, title: "Series", recurrence_rule: "FREQ=DAILY", start_at: 1.hour.from_now)
      create(:event, user: user, title: "One-off", start_at: 2.hours.from_now)

      get api_v1_events_path, headers: auth

      expect(body["events"].to_h { |event| [ event["title"], event["recurring"] ] }).to eq("Series" => true, "One-off" => false)
      expect(body["events"].first).not_to have_key("recurrence_rule")
    end
  end

  # 00:30 on Monday 5 October in Istanbul (+03:00).
  describe "writes" do
    let(:user) { create(:user, timezone: "Istanbul") }

    before { travel_to Time.utc(2026, 10, 4, 21, 30) }

    def create_event(**params)
      post api_v1_events_path, params: { title: "Dişçi", start_at: "2026-10-06T15:00", **params }, headers: auth, as: :json
    end

    def occurrences_of(event, from:, to:)
      get api_v1_events_path(from: from, to: to), headers: auth
      body["events"].find { |json| json["id"] == event.id }&.fetch("occurrences")
    end

    describe "GET /api/v1/events/:id" do
      it "returns the event with what the edit form needs" do
        event = create(:event, user: user, title: "Yoga", description: "Mat getir", location: "Stüdyo",
                               start_at: Time.utc(2026, 10, 6, 15), end_at: Time.utc(2026, 10, 6, 16),
                               recurrence_rule: "FREQ=WEEKLY;BYDAY=TU")

        get api_v1_event_path(event), headers: auth

        expect(response).to have_http_status(:ok)
        expect(body["event"]).to eq(
          "id" => event.id, "title" => "Yoga", "start_at" => "2026-10-06T18:00:00.000+03:00",
          "end_at" => "2026-10-06T19:00:00.000+03:00", "all_day" => false, "color" => "#B8860B",
          "event_type" => "personal", "location" => "Stüdyo", "duration_minutes" => 60, "recurring" => true,
          "description" => "Mat getir", "recurrence_rule" => "FREQ=WEEKLY;BYDAY=TU"
        )
      end

      it "404s for another user's event" do
        get api_v1_event_path(create(:event)), headers: auth

        expect(response).to have_http_status(:not_found)
        expect(body).to eq("error" => "not_found", "code" => "not_found")
      end

      it "401s without a token" do
        get api_v1_event_path(create(:event, user: user))

        expect(response).to have_http_status(:unauthorized)
      end
    end

    describe "POST /api/v1/events" do
      it "creates an event, reading times without an offset as the user's wall clock" do
        expect {
          create_event(end_at: "2026-10-06T15:45", location: "Kadıköy", description: "Kontrol", event_type: "health", color: "#6B8E5A")
        }.to change(user.events, :count).by(1)

        expect(response).to have_http_status(:created)
        expect(body["event"]).to include(
          "title" => "Dişçi", "start_at" => "2026-10-06T15:00:00.000+03:00", "end_at" => "2026-10-06T15:45:00.000+03:00",
          "duration_minutes" => 45, "location" => "Kadıköy", "description" => "Kontrol", "event_type" => "health",
          "color" => "#6B8E5A", "all_day" => false, "recurring" => false, "recurrence_rule" => nil
        )
        expect(user.events.sole.start_at).to eq(Time.utc(2026, 10, 6, 12))
      end

      it "keeps an explicit offset and fills in the web form's defaults" do
        create_event(start_at: "2026-10-06T12:00:00Z")

        expect(body["event"]).to include(
          "start_at" => "2026-10-06T15:00:00.000+03:00", "end_at" => nil, "event_type" => "personal", "color" => "#B8860B"
        )
      end

      it "422s with every validation error at once, end before start included" do
        expect {
          create_event(title: "", end_at: "2026-10-06T14:00", event_type: "party", color: "red")
        }.not_to change(Event, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(body["code"]).to eq("validation_failed")
        expect(body["details"]).to eq(
          "title" => [ { "error" => "blank" } ],
          "end_at" => [ { "error" => "must_be_after_start" } ],
          "event_type" => [ { "error" => "inclusion", "value" => "party" } ],
          "color" => [ { "error" => "invalid" } ]
        )
      end

      it "words the end-before-start error in the user's language" do
        user.update!(locale: "tr")

        create_event(end_at: "2026-10-06T15:00")

        expect(body["errors"]["end_at"]).to eq([ "Bitiş başlangıçtan sonra olmalı" ])
      end

      it "422s for a missing start" do
        create_event(start_at: nil)

        expect(body["details"]).to eq("start_at" => [ { "error" => "blank" } ])
      end

      it "422s with invalid_datetime for a start or end it cannot read" do
        [
          [ { start_at: "yarın 15:00" }, "start_at" ],
          [ { start_at: "2026-02-30T10:00" }, "start_at" ],
          [ { start_at: "2026-10-06T10:61" }, "start_at" ],
          [ { start_at: 1_791_302_400 }, "start_at" ],
          [ { end_at: "2026-10-06T16:00+25:00" }, "end_at" ]
        ].each do |params, param|
          expect { create_event(**params) }.not_to change(Event, :count)

          expect(body).to include("code" => "invalid_datetime", "param" => param)
          expect(body["errors"][param]).to eq([ "Use a date and time in ISO 8601 format, like 2026-10-05T09:00:00+03:00." ])
        end
      end

      describe "all-day events" do
        it "covers whole local days: 00:00 on the first, 23:59:59 on the last" do
          create_event(all_day: true, start_at: "2026-10-06", end_at: "2026-10-08")

          expect(response).to have_http_status(:created)
          expect(body["event"]).to include(
            "all_day" => true, "start_at" => "2026-10-06T00:00:00.000+03:00", "end_at" => "2026-10-08T23:59:59.000+03:00"
          )
        end

        it "drops the time of day from a datetime" do
          create_event(all_day: true, start_at: "2026-10-06T14:30:00+03:00")

          expect(body["event"]).to include("start_at" => "2026-10-06T00:00:00.000+03:00", "end_at" => nil)
        end

        it "422s when the last day is before the first" do
          create_event(all_day: true, start_at: "2026-10-06", end_at: "2026-10-05")

          expect(body["details"]).to eq("end_at" => [ { "error" => "must_be_after_start" } ])
        end

        it "422s for all_day that is not a boolean, or null" do
          [ "maybe", nil ].each do |value|
            create_event(all_day: value)

            expect(body).to include("code" => "invalid_parameter", "param" => "all_day")
          end
        end
      end

      describe "recurrence" do
        it "creates a series that GET /events expands" do
          create_event(recurrence_rule: "rrule:freq=weekly;byday=tu,th")

          expect(body["event"]).to include("recurring" => true, "recurrence_rule" => "FREQ=WEEKLY;BYDAY=TU,TH")
          event = Event.find(body["event"]["id"])
          expect(occurrences_of(event, from: "2026-10-05", to: "2026-10-16")).to eq(%w[2026-10-06 2026-10-08 2026-10-13 2026-10-15])
        end

        it "ends a series on the local day a date-only UNTIL names" do
          create_event(recurrence_rule: "FREQ=DAILY;UNTIL=20261008")

          expect(body["event"]["recurrence_rule"]).to eq("FREQ=DAILY;UNTIL=20261008T205959Z")
          event = Event.find(body["event"]["id"])
          expect(occurrences_of(event, from: "2026-10-05", to: "2026-10-31")).to eq(%w[2026-10-06 2026-10-07 2026-10-08])
        end

        it "ignores a recurring flag without a rule" do
          create_event(recurring: true)

          expect(body["event"]).to include("recurring" => false)
        end

        it "422s with a machine-readable reason for a rule it will not expand" do
          [
            [ "FREQ=MINUTELY", { "error" => "unsupported_frequency", "value" => "MINUTELY" } ],
            [ "FREQ=DAILY;BYHOUR=9,18", { "error" => "unsupported_part", "value" => "BYHOUR" } ],
            [ "FREQ=DAILY;INTERVAL=0", { "error" => "out_of_range", "part" => "INTERVAL", "minimum" => 1, "maximum" => 999 } ],
            [ "FREQ=DAILY;COUNT=5000", { "error" => "out_of_range", "part" => "COUNT", "minimum" => 1, "maximum" => 999 } ],
            [ "every tuesday", { "error" => "invalid" } ],
            [ "FREQ=DAILY;BYMONTH=#{Array.new(300, '1').join(',')}", { "error" => "too_long", "count" => 500 } ],
            [ "FREQ=DAILY;UNTIL=20261001", { "error" => "no_occurrences" } ]
          ].each do |rule, detail|
            expect { create_event(recurrence_rule: rule) }.not_to change(Event, :count)

            expect(response).to have_http_status(:unprocessable_content), rule
            expect(body["code"]).to eq("validation_failed")
            expect(body["details"]).to eq("recurrence_rule" => [ detail ])
          end
        end

        it "words a refused rule in the user's language" do
          user.update!(locale: "tr")

          create_event(recurrence_rule: "FREQ=HOURLY")

          expect(body["errors"]["recurrence_rule"]).to eq([ "Tekrar kuralı günlük, haftalık, aylık ya da yıllık olmalı" ])
        end

        it "422s for a rule that is not a string" do
          create_event(recurrence_rule: { "FREQ" => "DAILY" })

          expect(body).to include("code" => "invalid_parameter", "param" => "recurrence_rule")
        end
      end

      it "401s without a token" do
        expect { post api_v1_events_path, params: { title: "X", start_at: "2026-10-06T10:00" } }.not_to change(Event, :count)

        expect(response).to have_http_status(:unauthorized)
      end
    end

    describe "PATCH /api/v1/events/:id" do
      let(:event) do
        create(:event, user: user, title: "Standup", location: "Ofis", start_at: Time.utc(2026, 10, 6, 6),
                       end_at: Time.utc(2026, 10, 6, 6, 15), recurrence_rule: "FREQ=WEEKLY;BYDAY=TU,TH")
      end

      def patch_event(target = event, **params)
        patch api_v1_event_path(target), params: params, headers: auth, as: :json
      end

      it "changes only the keys sent" do
        patch_event(title: "Daily standup")

        expect(response).to have_http_status(:ok)
        expect(event.reload).to have_attributes(
          title: "Daily standup", location: "Ofis", start_at: Time.utc(2026, 10, 6, 6),
          end_at: Time.utc(2026, 10, 6, 6, 15), recurrence_rule: "FREQ=WEEKLY;BYDAY=TU,TH"
        )
      end

      it "edits the whole series: a new start moves every occurrence" do
        patch_event(start_at: "2026-10-07T10:00", end_at: "2026-10-07T10:15", recurrence_rule: "FREQ=WEEKLY;BYDAY=WE")

        expect(body["event"]).to include("start_at" => "2026-10-07T10:00:00.000+03:00", "recurrence_rule" => "FREQ=WEEKLY;BYDAY=WE")
        expect(occurrences_of(event, from: "2026-10-05", to: "2026-10-18")).to eq(%w[2026-10-07 2026-10-14])
      end

      it "stops the series with recurrence_rule null, leaving a one-off on the start date" do
        patch_event(recurrence_rule: nil)

        expect(body["event"]).to include("recurring" => false, "recurrence_rule" => nil)
        expect(occurrences_of(event, from: "2026-10-05", to: "2026-10-18")).to eq(%w[2026-10-06])
      end

      it "422s when a new start leaves a series with no occurrence" do
        event.update!(recurrence_rule: "FREQ=DAILY;COUNT=3")

        patch_event(start_at: "2026-10-06T09:00", recurrence_rule: "FREQ=DAILY;UNTIL=20261001")

        expect(body["details"]).to eq("recurrence_rule" => [ { "error" => "no_occurrences" } ])
        expect(event.reload.recurrence_rule).to eq("FREQ=DAILY;COUNT=3")
      end

      it "422s for an end before the start and changes nothing" do
        patch_event(title: "Moved", end_at: "2026-10-06T08:00")

        expect(response).to have_http_status(:unprocessable_content)
        expect(body["details"]).to eq("end_at" => [ { "error" => "must_be_after_start" } ])
        expect(event.reload.title).to eq("Standup")
      end

      it "spans whole days when the event becomes all-day" do
        patch_event(all_day: true)

        expect(body["event"]).to include(
          "all_day" => true, "start_at" => "2026-10-06T00:00:00.000+03:00", "end_at" => "2026-10-06T23:59:59.000+03:00"
        )
      end

      it "leaves the times of an older all-day event alone on a title edit" do
        event.update_columns(all_day: true)

        patch_event(title: "Renamed")

        expect(event.reload).to have_attributes(title: "Renamed", start_at: Time.utc(2026, 10, 6, 6))
      end

      it "404s for another user's event" do
        other = create(:event, title: "Theirs")

        patch_event(other, title: "Mine")

        expect(response).to have_http_status(:not_found)
        expect(other.reload.title).to eq("Theirs")
      end

      it "401s without a token" do
        patch api_v1_event_path(event), params: { title: "X" }

        expect(response).to have_http_status(:unauthorized)
        expect(event.reload.title).to eq("Standup")
      end
    end

    describe "DELETE /api/v1/events/:id" do
      it "deletes the event, the whole series for a recurring one" do
        event = create(:event, user: user, start_at: Time.utc(2026, 10, 6, 6), recurrence_rule: "FREQ=DAILY")

        delete api_v1_event_path(event), headers: auth

        expect(response).to have_http_status(:no_content)
        expect(Event.exists?(event.id)).to be(false)
        expect(occurrences_of(event, from: "2026-10-05", to: "2026-10-31")).to be_nil
      end

      it "404s for another user's event and deletes nothing" do
        other = create(:event)

        delete api_v1_event_path(other), headers: auth

        expect(response).to have_http_status(:not_found)
        expect(Event.exists?(other.id)).to be(true)
      end

      it "401s without a token" do
        event = create(:event, user: user)

        delete api_v1_event_path(event)

        expect(response).to have_http_status(:unauthorized)
        expect(Event.exists?(event.id)).to be(true)
      end
    end
  end
end
