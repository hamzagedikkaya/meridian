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

    it "falls back to the start date when the recurrence rule is invalid" do
      event = build(:event, user: user, recurring: true,
                            recurrence_rule: "not-a-valid-ical-rule",
                            start_at: Time.zone.local(2026, 6, 10, 9))

      expect(event.occurrences_between(from, to)).to eq([ Date.new(2026, 6, 10) ])
    end
  end
end
