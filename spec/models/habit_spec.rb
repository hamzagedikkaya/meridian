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
      habit = create(:habit, created_at: 60.days.ago)
      5.times { |i| habit.habit_logs.create!(date: i.days.ago.to_date, completed: true) }
      expect(habit.completion_rate(days: 10)).to eq(50.0)
    end

    it "counts only the days since the habit started" do
      habit = create(:habit, created_at: Time.current)
      habit.habit_logs.create!(date: Date.current, completed: true)
      expect(habit.completion_rate(days: 30)).to eq(100.0)

      started = create(:habit, created_at: 4.days.ago)
      started.habit_logs.create!(date: 1.day.ago.to_date, completed: true)
      expect(started.completion_rate(days: 30)).to eq(20.0)
    end

    it "counts logged days from before the start date as tracked" do
      habit = create(:habit, created_at: Time.current)
      habit.habit_logs.create!(date: 9.days.ago.to_date, completed: true)
      expect(habit.completion_rate(days: 30)).to eq(10.0)
    end

    it "ends an archived habit's window on the day it was archived" do
      habit = create(:habit, created_at: 60.days.ago, archived_at: 10.days.ago)
      5.times { |i| habit.habit_logs.create!(date: (10 + i).days.ago.to_date, completed: true) }
      expect(habit.completion_rate(days: 10)).to eq(50.0)
    end
  end

  describe "#tracked_window" do
    it "is the whole window for a habit older than it" do
      habit = create(:habit, created_at: 60.days.ago)
      expect(habit.tracked_window(days: 14)).to eq((Date.current - 13)..Date.current)
    end

    it "starts on the start date, or on an earlier logged day" do
      habit = create(:habit, created_at: 3.days.ago)
      expect(habit.tracked_window(days: 14)).to eq((Date.current - 3)..Date.current)

      habit.habit_logs.create!(date: 5.days.ago.to_date, completed: false, count: 0)
      expect(habit.tracked_window(days: 14)).to eq((Date.current - 5)..Date.current)

      habit.habit_logs.create!(date: 20.days.ago.to_date, completed: true)
      expect(habit.tracked_window(days: 14)).to eq((Date.current - 13)..Date.current)
    end

    it "always holds the end date" do
      habit = create(:habit, created_at: Time.current)
      expect(habit.tracked_window(days: 7, end_date: 3.days.ago.to_date)).to eq((Date.current - 3)..(Date.current - 3))
    end
  end

  describe "#chain_window" do
    let(:habit) { create(:habit, color: "#B8860B", created_at: 100.days.ago) }

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
      counter = create(:habit, target_count: 5, created_at: 100.days.ago)
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

    it "starts at the habit's start date, trimmed or not" do
      fresh = create(:habit, created_at: 2.days.ago)
      fresh.habit_logs.create!(date: Date.current, completed: true)
      [ true, false ].each do |trim|
        window = fresh.chain_window(days: 30, trim: trim)
        expect(window.map { |e| e[:status] }).to eq(trim ? [ :completed ] : [ :missed, :missed, :completed ])
      end
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
      h1 = create(:habit, created_at: 10.days.ago)
      h2 = create(:habit, user: h1.user, created_at: 10.days.ago)
      h1.habit_logs.create!(date: 1.day.ago.to_date, completed: true)
      h2.habit_logs.create!(date: Date.current, completed: true)

      result = described_class.chain_windows_for([ h1, h2 ], days: 3, trim: false)
      expect(result.keys).to contain_exactly(h1, h2)
      expect(result[h1].map { |e| e[:status] }).to eq([ :missed, :completed, :today_pending ])
      expect(result[h2].map { |e| e[:status] }).to eq([ :missed, :missed, :completed ])
    end

    it "starts each habit's window at its start date or earliest log" do
      old = create(:habit, created_at: 30.days.ago)
      fresh = create(:habit, user: old.user, created_at: Time.current)
      seeded = create(:habit, user: old.user, created_at: Time.current)
      started = create(:habit, user: old.user, created_at: 2.days.ago)
      seeded.habit_logs.create!(date: 40.days.ago.to_date, completed: true)
      seeded.habit_logs.create!(date: 2.days.ago.to_date, completed: true)

      result = described_class.chain_windows_for([ old, fresh, seeded, started ], days: 5, trim: false)
      expect(result[old].size).to eq(5)
      expect(result[fresh].map { |e| e[:status] }).to eq([ :today_pending ])
      expect(result[seeded].size).to eq(5)
      expect(result[started].map { |e| e[:date] }).to eq((Date.current - 2..Date.current).to_a)
    end

    it "returns an empty hash for no habits" do
      expect(described_class.chain_windows_for([])).to eq({})
    end
  end

  describe ".week_completion_pct" do
    include ActiveSupport::Testing::TimeHelpers

    # Wednesday: Monday through today is 3 days.
    before { travel_to Time.zone.local(2026, 6, 17, 12) }
    after  { travel_back }

    it "is 0 without habits" do
      expect(described_class.week_completion_pct([])).to eq(0)
    end

    it "is 100 for a habit created and done today" do
      habit = create(:habit, created_at: Time.current)
      habit.habit_logs.create!(date: Date.current, completed: true)
      expect(described_class.week_completion_pct([ habit ])).to eq(100)
    end

    it "weighs each habit by the days it existed this week" do
      old = create(:habit, created_at: 30.days.ago)
      fresh = create(:habit, user: old.user, created_at: 1.day.ago)
      [ 0, 1 ].each { |n| old.habit_logs.create!(date: Date.current - n, completed: true) }
      fresh.habit_logs.create!(date: Date.current, completed: true)
      # 3 completed of 3 + 2 days.
      expect(described_class.week_completion_pct([ old, fresh ])).to eq(60)
    end

    it "rounds an exact half up: 23 of 40 habit-days is 58, not the Float's 57" do
      travel_to Time.zone.local(2026, 6, 19, 12) # Friday: 5 days
      user = create(:user)
      habits = create_list(:habit, 8, user: user, created_at: 30.days.ago)
      days = (Date.new(2026, 6, 15)..Date.new(2026, 6, 19)).to_a
      habits.product(days).first(23).each { |habit, date| habit.habit_logs.create!(date: date, completed: true) }

      expect(described_class.week_completion_pct(habits)).to eq(58)
    end

    it "leaves out completions of habits not given (archived ones)" do
      habit = create(:habit, created_at: 30.days.ago)
      archived = create(:habit, user: habit.user, created_at: 30.days.ago, archived_at: 1.day.ago)
      archived.habit_logs.create!(date: Date.current - 2, completed: true)
      habit.habit_logs.create!(date: Date.current, completed: true)
      expect(described_class.week_completion_pct([ habit ])).to eq(33)
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

  describe "#set_log_count!" do
    let(:habit) { create(:habit, target_count: 3) }
    let(:day) { Date.current - 2 }

    it "stores a partial count for a daily habit without completing it" do
      log = habit.set_log_count!(day, 2)

      expect(log).to be_persisted
      expect(log).to have_attributes(date: day, count: 2, completed: false)
    end

    it "completes the day once the target is reached and clamps above it" do
      habit.set_log_count!(day, 7)

      expect(habit.habit_logs.find_by(date: day)).to have_attributes(count: 3, completed: true)
    end

    it "is idempotent: the same count twice leaves one log in the same state" do
      2.times { habit.set_log_count!(day, 2) }

      expect(habit.habit_logs.where(date: day).pluck(:count, :completed)).to eq([ [ 2, false ] ])
    end

    it "removes the log for count 0 and returns an unsaved empty log" do
      habit.set_log_count!(day, 3)

      log = habit.set_log_count!(day, 0)

      expect(log).not_to be_persisted
      expect(log).to have_attributes(date: day, count: 0, completed: false)
      expect(habit.habit_logs.where(date: day)).to be_empty
    end

    it "treats any positive count as a done day for weekly habits, as the web checkbox does" do
      weekly = create(:habit, frequency: "weekly", target_count: 3)

      expect(weekly.set_log_count!(day, 1)).to have_attributes(count: 3, completed: true)
      expect(weekly.period_completed_count(day)).to eq(1)
    end

    it "updates an existing log in place, keeping its note" do
      existing = habit.habit_logs.create!(date: day, count: 1, completed: false, note: "felt good")

      habit.set_log_count!(day, 3)

      expect(existing.reload).to have_attributes(count: 3, completed: true, note: "felt good")
    end
  end

  describe "#toggle_log!" do
    let(:habit) { create(:habit, target_count: 1) }

    it "flips an unlogged day to done and a done day back" do
      expect(habit.toggle_log!(Date.current)).to have_attributes(completed: true, count: 1)
      expect(habit.toggle_log!(Date.current)).to have_attributes(completed: false, count: 0)
    end

    it "moves the counter by delta within 0..target_count for multi-count habits" do
      counter = create(:habit, target_count: 3)

      expect(counter.toggle_log!(Date.current, delta: 2)).to have_attributes(count: 2, completed: false)
      expect(counter.toggle_log!(Date.current, delta: 5)).to have_attributes(count: 3, completed: true)
      expect(counter.toggle_log!(Date.current, delta: -9)).to have_attributes(count: 0, completed: false)
    end

    it "ignores the delta for single-count habits and flips instead" do
      expect(habit.toggle_log!(Date.current, delta: 1)).to have_attributes(completed: true, count: 1)
    end
  end

  describe "ownership and links" do
    it "refuses a goal of another user" do
      habit = build(:habit, goal: create(:goal))

      expect(habit).not_to be_valid
      expect(habit.errors.details[:goal_id]).to eq([ { error: :must_belong_to_same_user } ])
    end

    it "unlinks the goals that track it when destroyed, settled on its final count, on the web as in the API" do
      habit = create(:habit)
      goal = create(:goal, user: habit.user, target_type: "habit", related: habit, current_value: 1)
      3.times { |n| habit.habit_logs.create!(date: Date.current - n, completed: true, count: 1) }

      habit.destroy!

      expect(goal.reload).to have_attributes(related_type: nil, related_id: nil, current_value: 3)
    end
  end

  describe "#start_date, #last_active_date and #archived?" do
    it "starts on the day of creation and stays in use until today" do
      habit = create(:habit, created_at: 3.days.ago)

      expect(habit.start_date).to eq(Date.current - 3)
      expect(habit.last_active_date).to eq(Date.current)
      expect(habit).not_to be_archived
    end

    it "ends on the day it was archived" do
      habit = create(:habit, archived_at: 2.days.ago)

      expect(habit).to be_archived
      expect(habit.last_active_date).to eq(Date.current - 2)
    end
  end

  describe "frozen logs" do
    it "refuses #toggle_log! and #set_log_count! on an archived habit" do
      habit = create(:habit, archived_at: 1.day.ago)

      expect { habit.toggle_log!(Date.current) }.to raise_error(Habit::LogRefused) { |error| expect(error.code).to eq(:habit_archived) }
      expect { habit.set_log_count!(Date.current, 1) }.to raise_error(Habit::LogRefused)
      expect(habit.habit_logs).to be_empty
    end

    it "names why a day cannot be logged" do
      habit = create(:habit, created_at: 3.days.ago)

      expect(habit.log_refusal(Date.current)).to be_nil
      expect(habit.log_refusal(Date.current + 1)).to eq(:future_date)
      expect(habit.log_refusal(Date.current - 10)).to eq(:before_habit_start)
      habit.update!(archived_at: Time.current)
      expect(habit.log_refusal(Date.current)).to eq(:habit_archived)
    end
  end

  describe "deleting a habit" do
    it "deletes its logs in one statement" do
      habit = create(:habit)
      3.times { |n| habit.habit_logs.create!(date: Date.current - n, completed: true) }
      deletes = []
      counter = ->(*, payload) { deletes << payload[:sql] if payload[:sql].start_with?("DELETE FROM \"habit_logs\"") }

      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { habit.destroy! }

      expect(deletes.size).to eq(1)
      expect(HabitLog.where(habit_id: habit.id)).to be_empty
    end
  end

  describe "first log date lookups" do
    it "are read once for a whole list's chains and 30-day completion rates" do
      user = create(:user)
      habits = [ 3, 5, 20 ].map { |age| create(:habit, user: user, created_at: age.days.ago) }
      habits.each { |habit| habit.habit_logs.create!(date: Date.current, completed: true) }
      lookups = []
      counter = ->(*, payload) { lookups << payload[:sql] if payload[:sql].include?('MIN("habit_logs"."date")') }

      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        described_class.chain_windows_for(habits, days: 14)
        habits.each(&:completion_rate)
      end

      expect(lookups.size).to eq(1)
    end
  end
end
