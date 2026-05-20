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
end
