require 'rails_helper'

RSpec.describe JournalEntry, type: :model do
  describe "validations" do
    subject { build(:journal_entry) }

    it { is_expected.to validate_presence_of(:date) }
    it { is_expected.to validate_inclusion_of(:mood).in_array(described_class::MOODS).allow_nil }
    it { is_expected.to validate_inclusion_of(:energy_level).in_range(1..5).allow_nil }
  end

  describe "#tag_list" do
    it "splits comma-separated tags" do
      entry = build(:journal_entry, tags: "work, reflection,  weekend")
      expect(entry.tag_list).to eq(%w[work reflection weekend])
    end
  end

  describe "#mood_emoji" do
    it "returns the emoji for the mood" do
      expect(build(:journal_entry, mood: "great").mood_emoji).to eq("😄")
    end
  end

  describe ".current_streak_for" do
    let(:user) { create(:user) }

    it "is 0 with no entries" do
      expect(described_class.current_streak_for(user)).to eq(0)
    end

    it "counts consecutive days ending today" do
      [ 0, 1, 2 ].each { |n| create(:journal_entry, user: user, date: Date.current - n) }
      expect(described_class.current_streak_for(user)).to eq(3)
    end

    it "still counts when today isn't journaled yet but yesterday is" do
      [ 1, 2 ].each { |n| create(:journal_entry, user: user, date: Date.current - n) }
      expect(described_class.current_streak_for(user)).to eq(2)
    end

    it "treats multiple entries on one day as a single day" do
      create(:journal_entry, user: user, date: Date.current)
      create(:journal_entry, user: user, date: Date.current)
      create(:journal_entry, user: user, date: Date.current - 1)
      expect(described_class.current_streak_for(user)).to eq(2)
    end

    it "is 0 when the most recent entry is older than yesterday" do
      create(:journal_entry, user: user, date: Date.current - 3)
      expect(described_class.current_streak_for(user)).to eq(0)
    end

    it "stops at the first gap" do
      [ 0, 1, 3, 4 ].each { |n| create(:journal_entry, user: user, date: Date.current - n) }
      expect(described_class.current_streak_for(user)).to eq(2)
    end
  end
end
