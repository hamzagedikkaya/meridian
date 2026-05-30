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

  describe "#chain_window" do
    let(:habit) { create(:habit, color: "#B8860B") }

    it "returns one entry per day in the window, oldest first" do
      window = habit.chain_window(days: 7)
      expect(window.size).to eq(7)
      expect(window.first[:date]).to eq(6.days.ago.to_date)
      expect(window.last[:date]).to eq(Date.current)
      expect(window.map { |e| e[:color] }.uniq).to eq([ "#B8860B" ])
    end

    it "marks completed days, gaps as missed, and today as today_pending when unlogged" do
      habit.habit_logs.create!(date: 1.day.ago.to_date, completed: true)
      habit.habit_logs.create!(date: 3.days.ago.to_date, completed: true)
      window = habit.chain_window(days: 5)
      statuses = window.map { |e| e[:status] }
      # 4d ago, 3d ago, 2d ago, 1d ago, today
      expect(statuses).to eq([ :missed, :completed, :missed, :completed, :today_pending ])
    end

    it "marks today as :completed when there is a completed log for today" do
      habit.habit_logs.create!(date: Date.current, completed: true)
      window = habit.chain_window(days: 3)
      expect(window.last[:status]).to eq(:completed)
    end

    it "respects a custom end_date (today_pending only when end_date == today)" do
      habit.habit_logs.create!(date: 5.days.ago.to_date, completed: true)
      window = habit.chain_window(days: 3, end_date: 4.days.ago.to_date)
      # Window spans 6→5→4 days ago. End is in the past so its slot is :missed
      # (no today_pending allowed), and the only completion sits in the middle.
      expect(window.map { |e| e[:status] }).to eq([ :missed, :completed, :missed ])
    end
  end

  describe "#period_completed_count" do
    it "counts completions in the current week for weekly habits" do
      habit = create(:habit, frequency: "weekly", target_count: 3)
      habit.habit_logs.create!(date: Date.current.beginning_of_week, completed: true)
      habit.habit_logs.create!(date: Date.current.beginning_of_week + 2.days, completed: true)
      habit.habit_logs.create!(date: Date.current.beginning_of_week - 1.day, completed: true) # last week, excluded
      expect(habit.period_completed_count).to eq(2)
    end

    it "counts completions in the current month for monthly habits" do
      habit = create(:habit, frequency: "monthly", target_count: 1)
      habit.habit_logs.create!(date: Date.current.beginning_of_month, completed: true)
      habit.habit_logs.create!(date: Date.current.beginning_of_month - 1.day, completed: true) # last month
      expect(habit.period_completed_count).to eq(1)
    end

    it "counts only today for daily habits" do
      habit = create(:habit, frequency: "daily")
      habit.habit_logs.create!(date: Date.current, completed: true)
      habit.habit_logs.create!(date: 1.day.ago.to_date, completed: true)
      expect(habit.period_completed_count).to eq(1)
    end
  end

  describe "#period_complete?" do
    it "is true when count meets target_count in the period" do
      habit = create(:habit, frequency: "weekly", target_count: 2)
      2.times { |i| habit.habit_logs.create!(date: Date.current.beginning_of_week + i.days, completed: true) }
      expect(habit.period_complete?).to be(true)
    end

    it "is false when count is below target_count" do
      habit = create(:habit, frequency: "weekly", target_count: 3)
      habit.habit_logs.create!(date: Date.current.beginning_of_week, completed: true)
      expect(habit.period_complete?).to be(false)
    end
  end

  describe ".chain_windows_for" do
    it "returns a per-habit windowed map using a single underlying query" do
      h1 = create(:habit)
      h2 = create(:habit, user: h1.user)
      h1.habit_logs.create!(date: 1.day.ago.to_date, completed: true)
      h2.habit_logs.create!(date: Date.current, completed: true)

      result = described_class.chain_windows_for([ h1, h2 ], days: 3)
      expect(result.keys).to contain_exactly(h1, h2)
      expect(result[h1].map { |e| e[:status] }).to eq([ :missed, :completed, :today_pending ])
      expect(result[h2].map { |e| e[:status] }).to eq([ :missed, :missed, :completed ])
    end

    it "returns an empty hash for no habits" do
      expect(described_class.chain_windows_for([])).to eq({})
    end
  end
end
