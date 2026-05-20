require 'rails_helper'

RSpec.describe Goal, type: :model do
  describe "validations" do
    subject { build(:goal) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_inclusion_of(:target_type).in_array(described_class::TARGET_TYPES) }
    it { is_expected.to validate_inclusion_of(:status).in_array(described_class::STATUSES) }
  end

  describe "#progress_percent" do
    it "returns clamped percentage" do
      goal = build(:goal, current_value: 60, target_value: 100)
      expect(goal.progress_percent).to eq(60.0)
    end

    it "caps at 100" do
      goal = build(:goal, current_value: 250, target_value: 100)
      expect(goal.progress_percent).to eq(100.0)
    end

    it "returns 0 when target is zero" do
      goal = build(:goal, current_value: 10, target_value: 0)
      expect(goal.progress_percent).to eq(0)
    end
  end
end
