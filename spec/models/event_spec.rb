require 'rails_helper'

RSpec.describe Event, type: :model do
  describe "validations" do
    subject { build(:event) }

    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_presence_of(:start_at) }
    it { is_expected.to validate_inclusion_of(:event_type).in_array(described_class::EVENT_TYPES) }
  end

  describe "end_at validation" do
    it "rejects end_at before start_at" do
      e = build(:event, start_at: Time.current, end_at: 1.hour.ago)
      expect(e).not_to be_valid
    end

    it "reports it with a translatable error key" do
      event = build(:event, start_at: Time.zone.local(2026, 6, 10, 9), end_at: Time.zone.local(2026, 6, 10, 8))

      expect(event).not_to be_valid
      expect(event.errors.details[:end_at]).to eq([ { error: :must_be_after_start } ])
      expect(event.errors[:end_at]).to eq([ "must be after start" ])
    end
  end

  describe ".for_month" do
    let(:user) { create(:user) }

    it "includes events whose start_at falls within the given month" do
      in_month  = create(:event, user: user, start_at: Time.zone.local(2026, 6, 15, 10))
      out_month = create(:event, user: user, start_at: Time.zone.local(2026, 7, 1, 0, 5))

      results = described_class.for_month(2026, 6)

      expect(results).to include(in_month)
      expect(results).not_to include(out_month)
    end

    it "includes events on the first instant of the month (boundary)" do
      edge = create(:event, user: user, start_at: Time.zone.local(2026, 6, 1, 0, 0, 0))
      expect(described_class.for_month(2026, 6)).to include(edge)
    end

    it "includes events on the last instant of the month (boundary)" do
      edge = create(:event, user: user, start_at: Time.zone.local(2026, 6, 30, 23, 59, 59))
      expect(described_class.for_month(2026, 6)).to include(edge)
    end
  end

  describe ".for_day" do
    let(:user) { create(:user) }
    let(:day)  { Date.new(2026, 6, 10) }

    it "includes events occurring on the given day and excludes the next day" do
      today    = create(:event, user: user, start_at: Time.zone.local(2026, 6, 10, 9))
      tomorrow = create(:event, user: user, start_at: Time.zone.local(2026, 6, 11, 1))

      results = described_class.for_day(day)

      expect(results).to include(today)
      expect(results).not_to include(tomorrow)
    end
  end

  describe ".upcoming" do
    let(:user) { create(:user) }

    it "returns only future events ordered by start_at" do
      later   = create(:event, user: user, start_at: 3.hours.from_now)
      sooner  = create(:event, user: user, start_at: 1.hour.from_now)
      past    = create(:event, user: user, start_at: 1.hour.ago)

      results = described_class.upcoming

      expect(results).not_to include(past)
      expect(results.to_a).to eq([ sooner, later ])
    end
  end

  describe ".recurring" do
    let(:user) { create(:user) }

    it "returns only events flagged as recurring" do
      recurring     = create(:event, user: user, recurring: true)
      non_recurring = create(:event, user: user, recurring: false)

      results = described_class.recurring

      expect(results).to include(recurring)
      expect(results).not_to include(non_recurring)
    end
  end

  describe "#duration_minutes" do
    it "returns nil when end_at is absent" do
      event = build(:event, start_at: Time.current, end_at: nil)
      expect(event.duration_minutes).to be_nil
    end

    it "returns the number of minutes between start_at and end_at" do
      start_at = Time.zone.local(2026, 6, 10, 9, 0, 0)
      event = build(:event, start_at: start_at, end_at: start_at + 90.minutes)
      expect(event.duration_minutes).to eq(90)
    end
  end

  describe "#occurrences_between" do
    let(:user) { create(:user) }
    let(:from) { Date.new(2026, 6, 1) }
    let(:to)   { Date.new(2026, 6, 30) }

    it "returns the single start date for non-recurring events" do
      event = build(:event, user: user, recurring: false, start_at: Time.zone.local(2026, 6, 10, 9))
      expect(event.occurrences_between(from, to)).to eq([ Date.new(2026, 6, 10) ])
    end

    it "returns the single start date when recurring but recurrence_rule is blank" do
      event = build(:event, user: user, recurring: true, recurrence_rule: nil,
                            start_at: Time.zone.local(2026, 6, 10, 9))
      expect(event.occurrences_between(from, to)).to eq([ Date.new(2026, 6, 10) ])
    end

    it "materializes occurrences from a valid iCal recurrence rule" do
      event = build(:event, user: user, recurring: true,
                            recurrence_rule: "FREQ=DAILY;COUNT=3",
                            start_at: Time.zone.local(2026, 6, 10, 9))

      occurrences = event.occurrences_between(from, to)

      expect(occurrences).to eq([
        Date.new(2026, 6, 10),
        Date.new(2026, 6, 11),
        Date.new(2026, 6, 12)
      ])
    end

    it "includes the whole last day of a date window, so from == to finds that day's occurrence" do
      event = build(:event, user: user, recurring: true, recurrence_rule: "FREQ=DAILY",
                            start_at: Time.zone.local(2026, 6, 1, 9))

      expect(event.occurrences_between(Date.new(2026, 6, 10), Date.new(2026, 6, 10))).to eq([ Date.new(2026, 6, 10) ])
      expect(event.occurrences_between(Date.new(2026, 6, 10), Date.new(2026, 6, 12)).size).to eq(3)
    end

    it "reads date windows as whole days in the current zone" do
      Time.use_zone("Istanbul") do
        event = build(:event, user: user, recurring: true, recurrence_rule: "FREQ=DAILY",
                              start_at: Time.zone.local(2026, 6, 1, 0, 30))

        expect(event.occurrences_between(Date.new(2026, 6, 10), Date.new(2026, 6, 10))).to eq([ Date.new(2026, 6, 10) ])
      end
    end

    it "falls back to the start date when the recurrence rule is invalid" do
      event = build(:event, user: user, recurring: true,
                            recurrence_rule: "not-a-valid-ical-rule",
                            start_at: Time.zone.local(2026, 6, 10, 9))

      expect(event.occurrences_between(from, to)).to eq([ Date.new(2026, 6, 10) ])
    end

    # A rule stored before rules were validated is not expanded into one
    # occurrence per minute.
    it "treats a stored rule that would repeat more than once a day as a one-off" do
      event = create(:event, user: user, start_at: Time.zone.local(2026, 6, 10, 9))
      event.update_columns(recurring: true, recurrence_rule: "FREQ=MINUTELY")

      expect(event.reload.occurrences_between(from, to)).to eq([ Date.new(2026, 6, 10) ])
    end

    it "falls back to the start date when expanding the rule fails" do
      event = build(:event, user: user, recurring: true, recurrence_rule: "FREQ=DAILY",
                            start_at: Time.zone.local(2026, 6, 10, 9))
      schedule = instance_double(IceCube::Schedule, add_recurrence_rule: nil)
      allow(schedule).to receive(:occurrences_between).and_raise(StandardError)
      allow(IceCube::Schedule).to receive(:new).and_return(schedule)

      expect(event.occurrences_between(from, to)).to eq([ Date.new(2026, 6, 10) ])
    end

    it "starts weeks on Monday for an every-other-week rule" do
      event = build(:event, user: user, recurring: true, recurrence_rule: "FREQ=WEEKLY;INTERVAL=2;BYDAY=SU,MO",
                            start_at: Time.zone.local(2026, 6, 7, 9)) # a Sunday

      # Weeks of Jun 1-7 and Jun 15-21; ice_cube's Sunday weeks would give Jun 7, 8, 21, 22.
      expect(event.occurrences_between(Date.new(2026, 6, 7), Date.new(2026, 6, 22))).to eq([
        Date.new(2026, 6, 7), Date.new(2026, 6, 15), Date.new(2026, 6, 21)
      ])
    end
  end

  describe "recurrence rule" do
    let(:user) { create(:user) }
    let(:start_at) { Time.zone.local(2026, 6, 10, 9) }

    it "stores the rule in normal form and marks the event recurring" do
      event = create(:event, user: user, start_at: start_at, recurrence_rule: "rrule:freq=weekly; byday=we")

      expect(event).to have_attributes(recurrence_rule: "FREQ=WEEKLY;BYDAY=WE", recurring: true)
    end

    it "pins a date-only UNTIL to the end of that day in the current zone" do
      event = Time.use_zone("Istanbul") do
        create(:event, user: user, start_at: start_at, recurrence_rule: "FREQ=DAILY;UNTIL=20260612")
      end

      expect(event.recurrence_rule).to eq("FREQ=DAILY;UNTIL=20260612T205959Z")
      expect(event.occurrences_between(Date.new(2026, 6, 1), Date.new(2026, 6, 30)).last).to eq(Date.new(2026, 6, 12))
    end

    it "stops recurring when the rule is cleared" do
      event = create(:event, user: user, start_at: start_at, recurrence_rule: "FREQ=DAILY")

      event.update!(recurrence_rule: "")

      expect(event).to have_attributes(recurrence_rule: nil, recurring: false)
    end

    it "keeps the recurring flag of a row whose rule does not change" do
      event = create(:event, user: user, recurring: true)

      event.update!(title: "Renamed")

      expect(event.reload.recurring).to be(true)
    end

    it "refuses an unsupported rule with a machine-readable error" do
      event = build(:event, user: user, start_at: start_at, recurrence_rule: "FREQ=MINUTELY")

      expect(event).not_to be_valid
      expect(event.errors.details[:recurrence_rule]).to eq([ { error: :unsupported_frequency, value: "MINUTELY" } ])
      expect(event.errors[:recurrence_rule]).to eq([ "must repeat daily, weekly, monthly or yearly" ])
    end

    it "refuses a rule that never occurs from the start" do
      event = build(:event, user: user, start_at: start_at, recurrence_rule: "FREQ=DAILY;UNTIL=20260601T000000Z")

      expect(event).not_to be_valid
      expect(event.errors.details[:recurrence_rule]).to eq([ { error: :no_occurrences } ])
    end

    it "checks the rule again when the start moves past its end" do
      event = create(:event, user: user, start_at: start_at, recurrence_rule: "FREQ=DAILY;UNTIL=20260630T000000Z")

      expect(event.update(start_at: Time.zone.local(2026, 7, 10, 9))).to be(false)
      expect(event.errors.details[:recurrence_rule]).to eq([ { error: :no_occurrences } ])
    end

    it "leaves an older row with an unsupported rule editable when the rule is untouched" do
      event = create(:event, user: user, start_at: start_at)
      event.update_columns(recurring: true, recurrence_rule: "FREQ=DAILY;BYHOUR=9,18")

      expect(event.reload.update(title: "Renamed")).to be(true)
    end
  end
end
