require 'rails_helper'

RSpec.describe FocusSession, type: :model do
  describe "validations" do
    subject { build(:focus_session) }

    it { is_expected.to validate_inclusion_of(:mode).in_array(described_class::MODES) }
    it { is_expected.to validate_numericality_of(:duration_seconds).is_greater_than(0) }
    it { is_expected.to validate_presence_of(:started_at) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:todo).optional }
  end

  describe "scopes" do
    let(:user) { create(:user) }

    it ".today returns only sessions started today" do
      # Anchor to a stable mid-day timestamp so the test doesn't break around
      # midnight, where `1.hour.ago` lands on the previous calendar day.
      today_session = create(:focus_session, user: user, started_at: Time.current.beginning_of_day + 12.hours)
      _old_session  = create(:focus_session, user: user, started_at: 3.days.ago)
      expect(described_class.today).to include(today_session)
      expect(described_class.today.count).to eq(1)
    end

    it ".focus_only excludes break sessions" do
      focus = create(:focus_session, user: user, mode: "focus")
      _break_ = create(:focus_session, user: user, mode: "short_break")
      expect(described_class.focus_only).to contain_exactly(focus)
    end

    it ".completed returns only sessions with completed_at" do
      done = create(:focus_session, user: user, completed_at: Time.current)
      _ongoing = create(:focus_session, user: user, completed_at: nil)
      expect(described_class.completed).to contain_exactly(done)
    end
  end
end
