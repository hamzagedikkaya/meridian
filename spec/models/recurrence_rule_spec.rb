require "rails_helper"

RSpec.describe RecurrenceRule do
  def problem(rule)
    described_class.new(rule).problems.first&.then { |found| [ found.type, found.options ] }
  end

  describe ".normalize" do
    it "upper-cases the rule and drops an RRULE: prefix, whitespace and empty parts" do
      expect(described_class.normalize(" rrule:freq=weekly; byday=mo, we;; ")).to eq("FREQ=WEEKLY;BYDAY=MO,WE")
    end

    it "returns nil for a blank rule" do
      expect(described_class.normalize("  ")).to be_nil
      expect(described_class.normalize(nil)).to be_nil
    end

    it "pins a date-only UNTIL to the end of that day in the given zone, as a UTC instant" do
      zone = ActiveSupport::TimeZone["Istanbul"]

      expect(described_class.normalize("FREQ=DAILY;UNTIL=20261231", zone: zone)).to eq("FREQ=DAILY;UNTIL=20261231T205959Z")
    end

    it "reads an UNTIL time without Z as the zone's wall clock and keeps a UTC one" do
      zone = ActiveSupport::TimeZone["Istanbul"]

      expect(described_class.normalize("FREQ=DAILY;UNTIL=20261231T090000", zone: zone)).to eq("FREQ=DAILY;UNTIL=20261231T060000Z")
      expect(described_class.normalize("FREQ=DAILY;UNTIL=20261231T090000Z", zone: zone)).to eq("FREQ=DAILY;UNTIL=20261231T090000Z")
    end

    it "leaves an unreadable UNTIL as it is, for validation to refuse" do
      expect(described_class.normalize("FREQ=DAILY;UNTIL=20260230")).to eq("FREQ=DAILY;UNTIL=20260230")
    end
  end

  describe "validation" do
    it "accepts the daily, weekly, monthly and yearly rules a phone sends" do
      [
        "FREQ=DAILY",
        "FREQ=DAILY;INTERVAL=2;COUNT=10",
        "FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR",
        "FREQ=WEEKLY;BYDAY=MO,WE;UNTIL=20261231T205959Z",
        "FREQ=WEEKLY;INTERVAL=2;BYDAY=TU;WKST=SU",
        "FREQ=MONTHLY;BYMONTHDAY=15",
        "FREQ=MONTHLY;BYMONTHDAY=-1",
        "FREQ=MONTHLY;BYDAY=-1FR",
        "FREQ=YEARLY;BYMONTH=11;BYDAY=4TH",
        "FREQ=YEARLY;INTERVAL=999;COUNT=999"
      ].each do |rule|
        expect(described_class.new(rule)).to be_valid, rule
      end
    end

    it "refuses frequencies that would repeat more than once a day" do
      expect(problem("FREQ=HOURLY")).to eq([ :unsupported_frequency, { value: "HOURLY" } ])
      expect(problem("FREQ=MINUTELY;COUNT=5")).to eq([ :unsupported_frequency, { value: "MINUTELY" } ])
      expect(problem("FREQ=SECONDLY")).to eq([ :unsupported_frequency, { value: "SECONDLY" } ])
    end

    it "refuses parts that add times of day or that ice_cube would ignore or misread" do
      expect(problem("FREQ=DAILY;BYHOUR=9,18")).to eq([ :unsupported_part, { value: "BYHOUR" } ])
      expect(problem("FREQ=DAILY;BYMINUTE=0,30")).to eq([ :unsupported_part, { value: "BYMINUTE" } ])
      expect(problem("FREQ=MONTHLY;BYDAY=MO;BYSETPOS=-1")).to eq([ :unsupported_part, { value: "BYSETPOS" } ])
      expect(problem("FREQ=YEARLY;BYWEEKNO=20")).to eq([ :unsupported_part, { value: "BYWEEKNO" } ])
    end

    it "refuses a rule over 500 characters" do
      expect(problem("FREQ=WEEKLY;BYDAY=#{Array.new(200, 'MO').join(',')}")).to eq([ :too_long, { count: 500 } ])
    end

    it "keeps INTERVAL and COUNT within 1..999" do
      expect(problem("FREQ=DAILY;INTERVAL=0")).to eq([ :out_of_range, { part: "INTERVAL", minimum: 1, maximum: 999 } ])
      expect(problem("FREQ=DAILY;COUNT=1000")).to eq([ :out_of_range, { part: "COUNT", minimum: 1, maximum: 999 } ])
      expect(problem("FREQ=DAILY;COUNT=999999999999")).to eq([ :out_of_range, { part: "COUNT", minimum: 1, maximum: 999 } ])
    end

    [
      "not-a-rule",
      "INTERVAL=2",
      "FREQ=DAILY;FREQ=WEEKLY",
      "FREQ=DAILY;INTERVAL=two",
      "FREQ=DAILY;COUNT=5;UNTIL=20261231T000000Z",
      "FREQ=DAILY;UNTIL=20260230",
      "FREQ=DAILY;UNTIL=soon",
      "FREQ=DAILY;UNTIL=20261231T240000",
      "FREQ=WEEKLY;BYDAY=XX",
      "FREQ=WEEKLY;BYDAY=1MO",
      "FREQ=YEARLY;BYDAY=1MO",
      # ice_cube would keep these to the start month; RFC 5545 means the year.
      "FREQ=YEARLY;BYDAY=MO",
      "FREQ=YEARLY;BYMONTHDAY=15",
      "FREQ=MONTHLY;BYMONTHDAY=0",
      "FREQ=MONTHLY;BYMONTHDAY=32",
      "FREQ=YEARLY;BYMONTH=13",
      "FREQ=WEEKLY;WKST=XX",
      "FREQ=DAILY;INTERVAL=2=3"
    ].each do |rule|
      it "refuses #{rule.inspect} as unreadable" do
        expect(problem(rule)).to eq([ :invalid, {} ])
      end
    end
  end

  it "refuses a rule ice_cube cannot build even when its parts look right" do
    allow(IceCube::Rule).to receive(:from_ical).and_raise(ArgumentError, "unexpected")

    expect(problem("FREQ=DAILY")).to eq([ :invalid, {} ])
  end

  describe "#to_ice_cube" do
    it "starts weeks on Monday unless WKST says otherwise, as RFC 5545 does" do
      start = Time.zone.local(2026, 10, 4, 9) # a Sunday
      dates = lambda do |rule|
        schedule = IceCube::Schedule.new(start)
        schedule.add_recurrence_rule(described_class.new(rule).to_ice_cube)
        schedule.occurrences_between(start, start + 3.weeks).map(&:to_date)
      end

      expect(dates.call("FREQ=WEEKLY;INTERVAL=2;BYDAY=SU,MO")).to eq([ Date.new(2026, 10, 4), Date.new(2026, 10, 12), Date.new(2026, 10, 18) ])
      expect(dates.call("FREQ=WEEKLY;INTERVAL=2;BYDAY=SU,MO;WKST=SU")).to eq([ Date.new(2026, 10, 4), Date.new(2026, 10, 5), Date.new(2026, 10, 18), Date.new(2026, 10, 19) ])
    end

    it "raises for a rule that is not valid" do
      expect { described_class.new("FREQ=MINUTELY").to_ice_cube }.to raise_error(ArgumentError)
    end
  end

  describe "#occurs_from?" do
    let(:start) { Time.zone.local(2026, 10, 5, 9) }

    it "is true when the series has an occurrence within ten years of its start" do
      expect(described_class.new("FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29").occurs_from?(start)).to be(true)
    end

    it "is false when UNTIL is before the start or the pattern never matches" do
      expect(described_class.new("FREQ=DAILY;UNTIL=20261001T000000Z").occurs_from?(start)).to be(false)
      expect(described_class.new("FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=30").occurs_from?(start)).to be(false)
    end
  end
end
