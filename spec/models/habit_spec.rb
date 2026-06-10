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
      window = habit.chain_window(days: 7, trim: false)
      expect(window.size).to eq(7)
      expect(window.first[:date]).to eq(6.days.ago.to_date)
      expect(window.last[:date]).to eq(Date.current)
      expect(window.map { |e| e[:color] }.uniq).to eq([ "#B8860B" ])
    end

    it "marks completed days, gaps as missed, and today as today_pending when unlogged" do
      habit.habit_logs.create!(date: 1.day.ago.to_date, completed: true)
      habit.habit_logs.create!(date: 3.days.ago.to_date, completed: true)
      window = habit.chain_window(days: 5, trim: false)
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
      window = habit.chain_window(days: 3, end_date: 4.days.ago.to_date, trim: false)
      # Window spans 6→5→4 days ago. End is in the past so its slot is :missed
      # (no today_pending allowed), and the only completion sits in the middle.
      expect(window.map { |e| e[:status] }).to eq([ :missed, :completed, :missed ])
    end

    it "marks counter days with partial progress (count > 0, count < target_count) as :partial" do
      counter = create(:habit, target_count: 5)
      counter.habit_logs.create!(date: Date.current, completed: false, count: 3)
      counter.habit_logs.create!(date: 1.day.ago.to_date, completed: false, count: 2)
      window = counter.chain_window(days: 3, trim: false)
      # 2d ago: no log → missed, 1d ago: partial, today: partial (not today_pending).
      statuses = window.map { |e| e[:status] }
      expect(statuses).to eq([ :missed, :partial, :partial ])
      today_entry = window.last
      expect(today_entry[:completed]).to eq(3)
      expect(today_entry[:possible]).to eq(5)
    end

    it "trims leading missed days so the chain starts at the first completion" do
      habit.habit_logs.create!(date: 2.days.ago.to_date, completed: true)
      window = habit.chain_window(days: 7)
      # 6→3 days ago were all missed; chain should now start at 2 days ago.
      expect(window.first[:date]).to eq(2.days.ago.to_date)
      expect(window.first[:status]).to eq(:completed)
      expect(window.size).to eq(3) # 2d ago, 1d ago, today
    end

    it "collapses to a single today entry when there is no completion or partial in the window" do
      window = habit.chain_window(days: 14)
      expect(window.size).to eq(1)
      expect(window.first[:date]).to eq(Date.current)
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

      result = described_class.chain_windows_for([ h1, h2 ], days: 3, trim: false)
      expect(result.keys).to contain_exactly(h1, h2)
      expect(result[h1].map { |e| e[:status] }).to eq([ :missed, :completed, :today_pending ])
      expect(result[h2].map { |e| e[:status] }).to eq([ :missed, :missed, :completed ])
    end

    it "returns an empty hash for no habits" do
      expect(described_class.chain_windows_for([])).to eq({})
    end
  end

  describe ".streaks_for" do
    it "returns an empty hash for no habits" do
      expect(described_class.streaks_for([])).to eq({})
    end

    it "computes the current streak per habit in a single batched query" do
      h1 = create(:habit)
      h2 = create(:habit, user: h1.user)
      # h1: today, yesterday, 2d ago → streak of 3 ending today.
      [ 0, 1, 2 ].each { |i| h1.habit_logs.create!(date: i.days.ago.to_date, completed: true) }
      # h2: yesterday only → streak of 1 ending yesterday.
      h2.habit_logs.create!(date: 1.day.ago.to_date, completed: true)

      result = described_class.streaks_for([ h1, h2 ])
      expect(result).to eq(h1.id => 3, h2.id => 1)
    end

    it "counts a streak that ends yesterday when today is not yet logged" do
      habit = create(:habit)
      [ 1, 2, 3 ].each { |i| habit.habit_logs.create!(date: i.days.ago.to_date, completed: true) }
      expect(described_class.streaks_for([ habit ])).to eq(habit.id => 3)
    end

    it "resets at a broken streak, counting only days back to the cutoff" do
      habit = create(:habit)
      habit.habit_logs.create!(date: Date.current, completed: true)
      habit.habit_logs.create!(date: 1.day.ago.to_date, completed: false)
      habit.habit_logs.create!(date: 2.days.ago.to_date, completed: true)
      expect(described_class.streaks_for([ habit ])).to eq(habit.id => 1)
    end

    it "is 0 when the most recent completion is older than yesterday" do
      habit = create(:habit)
      habit.habit_logs.create!(date: 10.days.ago.to_date, completed: true)
      expect(described_class.streaks_for([ habit ])).to eq(habit.id => 0)
    end

    it "is 0 for a habit with no completed logs" do
      habit = create(:habit)
      expect(described_class.streaks_for([ habit ])).to eq(habit.id => 0)
    end

    it "ignores future-dated logs and matches #current_streak" do
      habit = create(:habit)
      [ 0, 1 ].each { |i| habit.habit_logs.create!(date: i.days.ago.to_date, completed: true) }
      habit.habit_logs.create!(date: 1.day.from_now.to_date, completed: true) # future, excluded
      expect(described_class.streaks_for([ habit ])).to eq(habit.id => habit.current_streak)
      expect(habit.current_streak).to eq(2)
    end
  end

  describe "#longest_streak" do
    let(:habit) { create(:habit) }

    it "is 0 when there are no completed logs" do
      expect(habit.longest_streak).to eq(0)
    end

    it "is 1 for a single isolated completed day" do
      habit.habit_logs.create!(date: 5.days.ago.to_date, completed: true)
      expect(habit.longest_streak).to eq(1)
    end

    it "finds the longest run even when it is in the past, not the current streak" do
      # 3 consecutive days, a gap, then 2 consecutive → longest is 3.
      [ 10, 9, 8 ].each { |i| habit.habit_logs.create!(date: i.days.ago.to_date, completed: true) }
      [ 1, 0 ].each { |i| habit.habit_logs.create!(date: i.days.ago.to_date, completed: true) }
      expect(habit.longest_streak).to eq(3)
      expect(habit.current_streak).to eq(2)
    end

    it "ignores non-completed logs when measuring runs" do
      habit.habit_logs.create!(date: 3.days.ago.to_date, completed: true)
      habit.habit_logs.create!(date: 2.days.ago.to_date, completed: false) # breaks the run
      habit.habit_logs.create!(date: 1.day.ago.to_date, completed: true)
      habit.habit_logs.create!(date: Date.current, completed: true)
      expect(habit.longest_streak).to eq(2)
    end
  end
end
