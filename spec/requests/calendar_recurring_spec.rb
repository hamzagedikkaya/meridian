require "rails_helper"

# Series and all-day events created through the API show on the web too.
RSpec.describe "Web calendar, dashboard and feed with recurring events", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, timezone: "Istanbul") }

  around do |example|
    Time.use_zone("Istanbul") { travel_to(Time.zone.local(2026, 11, 10, 12)) { example.run } }
  end

  before do
    sign_in user
    create(:event, user: user, title: "Weekly yoga", start_at: Time.zone.local(2026, 10, 6, 18),
                   recurring: true, recurrence_rule: "FREQ=WEEKLY;BYDAY=TU")
    create(:event, user: user, title: "Day off", all_day: true,
                   start_at: Time.zone.local(2026, 11, 11), end_at: Time.zone.local(2026, 11, 11, 23, 59, 59))
  end

  it "shows a series anchored in an earlier month in the month view" do
    get calendar_month_path(2026, 11)

    expect(response.body.scan("Weekly yoga").size).to be >= 4
  end

  it "shows each occurrence of a series and all-day events in the week view" do
    get calendar_week_at_path("2026-11-09")

    expect(response.body).to include("Weekly yoga")
    expect(response.body).to include('data-testid="all-day-row"')
    expect(response.body).to include("Day off")
  end

  it "counts today's occurrence on the dashboard" do
    get root_path

    expect(response.body).to include("Weekly yoga")
  end

  it "exports a series with its RRULE and an all-day event as dates" do
    get calendar_feed_path

    expect(response.body).to include("SUMMARY:Weekly yoga")
    expect(response.body).to include("RRULE:FREQ=WEEKLY;BYDAY=TU")
    expect(response.body).to include("DTSTART;TZID=Europe/Istanbul:20261006T180000\r\n")
    expect(response.body).to include("DTSTART;VALUE=DATE:20261111\r\nDTEND;VALUE=DATE:20261112")
  end

  # A client expands an RRULE in DTSTART's zone. From a UTC start
  # (20261108T220000Z) an Istanbul Monday/Wednesday 01:00 series landed on
  # Sundays and Tuesdays in UTC, Tuesdays and Thursdays in the app's eyes.
  describe "a timed series" do
    let!(:series) do
      create(:event, user: user, title: "Night shift", start_at: Time.zone.local(2026, 11, 9, 1),
                     end_at: Time.zone.local(2026, 11, 9, 2), recurring: true, recurrence_rule: "FREQ=WEEKLY;BYDAY=MO,WE")
    end

    def vevent(event)
      get calendar_feed_path
      response.body[/BEGIN:VEVENT\r\nUID:meridian-#{event.id}@local\r\n.*?END:VEVENT/m]
    end

    it "is exported in the user's zone (TZID), not as a UTC instant" do
      text = vevent(series)

      expect(text).to include("DTSTART;TZID=Europe/Istanbul:20261109T010000\r\nDTEND;TZID=Europe/Istanbul:20261109T020000\r\n")
      expect(text).to include("RRULE:FREQ=WEEKLY;BYDAY=MO,WE\r\n")
      expect(text).not_to include("T220000Z")
    end

    it "comes with the zone's VTIMEZONE before the events" do
      get calendar_feed_path
      body = response.body

      expect(body).to include("BEGIN:VTIMEZONE\r\nTZID:Europe/Istanbul\r\n")
      expect(body[/BEGIN:VTIMEZONE.*?END:VTIMEZONE/m]).to include("TZOFFSETTO:+0300")
      expect(body.index("END:VTIMEZONE")).to be < body.index("BEGIN:VEVENT")
    end

    # The days a client gets: the rule expanded from DTSTART's wall clock in
    # its TZID, as RFC 5545 §3.3.10 reads it; the server lists the same.
    it "expands on Mondays and Wednesdays, the days the server lists" do
      text = vevent(series)
      local_start = Time.find_zone("Europe/Istanbul").parse(text[/DTSTART;TZID=Europe\/Istanbul:(\S+)/, 1])
      schedule = IceCube::Schedule.new(local_start)
      schedule.add_recurrence_rule(RecurrenceRule.new(text[/RRULE:(\S+)/, 1]).to_ice_cube)
      client_days = schedule.first(4).map(&:to_date)

      expect(client_days.map(&:wday).uniq).to contain_exactly(1, 3)
      expect(client_days).to eq(series.occurrences_between(Date.new(2026, 11, 9), Date.new(2026, 11, 19)))
    end

    it "leaves a one-off a UTC instant" do
      one_off = create(:event, user: user, title: "Dentist", start_at: Time.zone.local(2026, 11, 20, 1))

      expect(vevent(one_off)).to include("DTSTART:20261119T220000Z\r\n")
    end
  end

  # RFC 5545 counts DTSTART as an instance even where the rule does not
  # match, and skips a month without the start's day; ice_cube (the server)
  # does neither. The feed spells each series the server's way.
  describe "a series the two readings expand differently" do
    def vevent(event)
      get calendar_feed_path
      response.body[/BEGIN:VEVENT\r\nUID:meridian-#{event.id}@local\r\n.*?END:VEVENT/m]
    end

    it "starts at the first day the rule matches" do
      event = create(:event, user: user, title: "Gym", start_at: Time.zone.local(2026, 11, 8, 19),
                             end_at: Time.zone.local(2026, 11, 8, 20, 30), recurrence_rule: "FREQ=WEEKLY;BYDAY=MO,WE")

      text = vevent(event)

      expect(text).to include("DTSTART;TZID=Europe/Istanbul:20261109T190000\r\nDTEND;TZID=Europe/Istanbul:20261109T203000\r\n")
      expect(text).to include("RRULE:FREQ=WEEKLY;BYDAY=MO,WE\r\n")
      expect(event.occurrences_between(Date.new(2026, 11, 1), Date.new(2026, 11, 30)).first).to eq(Date.new(2026, 11, 9))
    end

    it "starts an all-day series at its first matching day, as long as it was" do
      event = create(:event, user: user, title: "Market", all_day: true, start_at: Time.zone.local(2026, 11, 2),
                             end_at: Time.zone.local(2026, 11, 3, 23, 59, 59), recurrence_rule: "FREQ=WEEKLY;BYDAY=TU")

      expect(vevent(event)).to include("DTSTART;VALUE=DATE:20261103\r\nDTEND;VALUE=DATE:20261105\r\n")
    end

    it "puts a monthly series from the 31st on shorter months' last day" do
      event = create(:event, user: user, title: "Rent", start_at: Time.zone.local(2027, 1, 31, 9), recurrence_rule: "FREQ=MONTHLY")

      text = vevent(event)

      expect(text).to include("DTSTART;TZID=Europe/Istanbul:20270131T090000\r\n")
      expect(text).to include("RRULE:FREQ=MONTHLY;BYMONTHDAY=-1\r\n")
      expect(event.occurrences_between(Date.new(2027, 2, 1), Date.new(2027, 2, 28))).to eq([ Date.new(2027, 2, 28) ])
    end

    it "lists a counted series no single rule spells as RDATEs" do
      event = create(:event, user: user, title: "Audit", start_at: Time.zone.local(2027, 1, 30, 9),
                             recurrence_rule: "FREQ=YEARLY;INTERVAL=2;BYMONTH=2,4;COUNT=3")

      text = vevent(event)

      expect(text).to include("DTSTART;TZID=Europe/Istanbul:20270228T090000\r\n")
      expect(text).not_to include("RRULE:")
      expect(text.scan(/^RDATE.*$/).map(&:chomp)).to eq(
        [ "RDATE;TZID=Europe/Istanbul:20270430T090000", "RDATE;TZID=Europe/Istanbul:20290228T090000" ]
      )
    end

    it "leaves out a stored series that never occurs" do
      event = create(:event, user: user, title: "Never", start_at: Time.zone.local(2026, 1, 1, 9))
      event.update_columns(recurring: true, recurrence_rule: "FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=30")

      get calendar_feed_path

      expect(response.body).not_to include("SUMMARY:Never")
    end
  end

  it "writes an all-day series' UNTIL as a date" do
    create(:event, user: user, title: "Leave", all_day: true, start_at: Time.zone.local(2026, 11, 2),
                   recurring: true, recurrence_rule: "FREQ=DAILY;UNTIL=20261130")

    get calendar_feed_path

    expect(response.body).to include("RRULE:FREQ=DAILY;UNTIL=20261130\r\n")
  end
end
