require "rails_helper"

# The feed's DTSTART and RRULE for a series, written so that RFC 5545
# expansion gives the days ice_cube (Event#occurrences_between) lists.
RSpec.describe IcalRecurrence do
  around { |example| Time.use_zone("Istanbul") { example.run } }

  def series(rule, start, all_day: false)
    event = build(:event, start_at: start, all_day: all_day, recurring: true, recurrence_rule: rule)
    described_class.new(event, RecurrenceRule.new(rule))
  end

  def local(*parts)
    Time.zone.local(*parts)
  end

  describe "#first_start" do
    it "is the first day the rule matches when the start does not" do
      # A Sunday start of a Monday/Wednesday series: RFC 5545 would count the
      # Sunday as an instance, the server never lists it.
      expect(series("FREQ=WEEKLY;BYDAY=MO,WE", local(2026, 11, 8, 10)).first_start).to eq(local(2026, 11, 9, 10))
    end

    it "keeps the interval's alignment" do
      expect(series("FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE", local(2026, 11, 8, 10)).first_start).to eq(local(2026, 11, 16, 10))
    end

    it "is the start when the rule matches it" do
      expect(series("FREQ=WEEKLY;BYDAY=TU", local(2026, 10, 6, 18)).first_start).to eq(local(2026, 10, 6, 18))
    end

    it "is found beyond a year" do
      expect(series("FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29", local(2025, 3, 1, 9)).first_start).to eq(local(2028, 2, 29, 9))
    end

    it "is nil for a series that never occurs" do
      expect(series("FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=30", local(2026, 1, 1, 9)).first_start).to be_nil
    end
  end

  describe "#rules" do
    it "leaves a rule both readings agree on as stored" do
      expect(series("FREQ=WEEKLY;BYDAY=MO,WE;UNTIL=20261231T205959Z", local(2026, 11, 9, 1)).rules)
        .to eq([ "FREQ=WEEKLY;BYDAY=MO,WE;UNTIL=20261231T205959Z" ])
      expect(series("FREQ=MONTHLY;BYMONTHDAY=31", local(2027, 1, 31, 9)).rules).to eq([ "FREQ=MONTHLY;BYMONTHDAY=31" ])
      expect(series("FREQ=MONTHLY", local(2027, 1, 28, 9)).rules).to eq([ "FREQ=MONTHLY" ])
      expect(series("FREQ=YEARLY", local(2027, 1, 31, 9)).rules).to eq([ "FREQ=YEARLY" ])
    end

    it "puts a series on the 31st on each month's last day" do
      expect(series("FREQ=MONTHLY;INTERVAL=2", local(2027, 1, 31, 9)).rules).to eq([ "FREQ=MONTHLY;INTERVAL=2;BYMONTHDAY=-1" ])
    end

    it "puts a series on the 29th or 30th on the latest of those days a month has" do
      expect(series("FREQ=MONTHLY;COUNT=5", local(2027, 1, 30, 9)).rules).to eq([ "FREQ=MONTHLY;COUNT=5;BYMONTHDAY=28,29,30;BYSETPOS=-1" ])
      expect(series("FREQ=MONTHLY", local(2027, 1, 29, 9)).rules).to eq([ "FREQ=MONTHLY;BYMONTHDAY=28,29;BYSETPOS=-1" ])
    end

    it "puts a yearly series on 29 February on 28 February in common years" do
      expect(series("FREQ=YEARLY", local(2028, 2, 29, 9)).rules).to eq([ "FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=28,29;BYSETPOS=-1" ])
    end

    it "makes a yearly series in several months monthly, so each month gets its day" do
      recurrence = series("FREQ=YEARLY;BYMONTH=2,4", local(2027, 1, 31, 9))

      expect(recurrence.rules).to eq([ "FREQ=MONTHLY;BYMONTH=2,4;BYMONTHDAY=-1" ])
      expect(recurrence.first_start).to eq(local(2027, 2, 28, 9))
    end

    it "writes one rule per month for such a series every other year" do
      expect(series("FREQ=YEARLY;INTERVAL=2;BYMONTH=2,4", local(2027, 1, 30, 9)).rules).to eq(
        [ "FREQ=YEARLY;INTERVAL=2;BYMONTH=2;BYMONTHDAY=28,29,30;BYSETPOS=-1",
          "FREQ=YEARLY;INTERVAL=2;BYMONTH=4;BYMONTHDAY=28,29,30;BYSETPOS=-1" ]
      )
    end
  end

  describe "#rdates" do
    it "lists a counted series no single rule spells" do
      recurrence = series("FREQ=YEARLY;INTERVAL=2;BYMONTH=2,4;COUNT=3", local(2027, 1, 30, 9))

      expect(recurrence.rules).to eq([])
      expect(recurrence.first_start).to eq(local(2027, 2, 28, 9))
      expect(recurrence.rdates).to eq([ local(2027, 4, 30, 9), local(2029, 2, 28, 9) ])
    end

    it "is empty when a rule is written" do
      expect(series("FREQ=MONTHLY", local(2027, 1, 31, 9)).rdates).to eq([])
    end
  end
end
