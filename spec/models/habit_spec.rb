require 'rails_helper'

RSpec.describe Habit, type: :model do
  describe "validations" do
    subject { build(:habit) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_inclusion_of(:frequency).in_array(described_class::FREQUENCIES) }
    it { is_expected.to validate_numericality_of(:target_count).is_greater_than(0) }
  end

  describe "#current_streak" do
    let(:habit) { create(:habit) }

    it "counts consecutive completed days ending today" do
      [ 0, 1, 2 ].each { |i| habit.habit_logs.create!(date: i.days.ago.to_date, completed: true) }
      expect(habit.current_streak).to eq(3)
    end

    it "stops at the first missing day" do
      habit.habit_logs.create!(date: Date.current, completed: true)
      habit.habit_logs.create!(date: 1.day.ago.to_date, completed: false)
      habit.habit_logs.create!(date: 2.days.ago.to_date, completed: true)
      expect(habit.current_streak).to eq(1)
    end

    it "is 0 when no recent completions" do
      habit.habit_logs.create!(date: 10.days.ago.to_date, completed: true)
      expect(habit.current_streak).to eq(0)
    end
  end

  describe "#completion_rate" do
    it "returns percentage of completed days in window" do
      habit = create(:habit)
      5.times { |i| habit.habit_logs.create!(date: i.days.ago.to_date, completed: true) }
      expect(habit.completion_rate(days: 10)).to eq(50.0)
    end
  end
end
