require "rails_helper"

RSpec.describe IcalTimeZone do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 10, 5, 12)) { example.run } }

  def components(ical)
    ical.scan(/BEGIN:(STANDARD|DAYLIGHT)\r\n(.*?)END:\1/m).map { |kind, body| [ kind, body.split("\r\n") ] }
  end

  it "describes a zone without clock changes as one standard observance" do
    ical = described_class.new(ActiveSupport::TimeZone["Istanbul"], from: Time.utc(2026, 10, 1)).to_ical

    expect(ical).to start_with("BEGIN:VTIMEZONE\r\nTZID:Europe/Istanbul\r\n")
    expect(ical).to end_with("END:VTIMEZONE\r\n")
    expect(components(ical)).to eq([
      [ "STANDARD", [ "DTSTART:20261001T030000", "TZOFFSETFROM:+0300", "TZOFFSETTO:+0300", "TZNAME:+03" ] ]
    ])
  end

  it "lists the changes from the series' start, then repeats a zone's yearly rules" do
    ical = described_class.new(ActiveSupport::TimeZone["Berlin"], from: Time.utc(2026, 1, 1)).to_ical
    parts = components(ical)

    expect(parts.first).to eq([ "STANDARD", [ "DTSTART:20260101T010000", "TZOFFSETFROM:+0100", "TZOFFSETTO:+0100", "TZNAME:CET" ] ])
    expect(parts).to include([ "DAYLIGHT", [ "DTSTART:20260329T020000", "TZOFFSETFROM:+0100", "TZOFFSETTO:+0200", "TZNAME:CEST" ] ])
    expect(parts).to include([ "DAYLIGHT", [ "DTSTART:20270328T020000", "RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU",
                                             "TZOFFSETFROM:+0100", "TZOFFSETTO:+0200", "TZNAME:CEST" ] ])
    expect(parts).to include([ "STANDARD", [ "DTSTART:20271031T030000", "RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU",
                                             "TZOFFSETFROM:+0200", "TZOFFSETTO:+0100", "TZNAME:CET" ] ])
    expect(parts.size).to eq(5)
  end

  it "finds an nth-weekday rule (New York: second Sunday of March, first of November)" do
    ical = described_class.new(ActiveSupport::TimeZone["Eastern Time (US & Canada)"], from: Time.utc(2026, 6, 1)).to_ical

    expect(ical).to include("RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=2SU\r\n")
    expect(ical).to include("RRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=1SU\r\n")
    expect(ical).to include("TZOFFSETFROM:-0500\r\nTZOFFSETTO:-0400\r\n")
  end
end
