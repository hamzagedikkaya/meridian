require 'rails_helper'

RSpec.describe PerfectDayChain do
  let(:user) { create(:user) }

  it "marks days with no active habits as :no_habits" do
    chain = described_class.new(user, days: 3, trim: false).to_a
    expect(chain.map { |e| e[:status] }).to eq([ :no_habits, :no_habits, :no_habits ])
  end

  it "is :perfect when every active habit is completed that day" do
    h1 = create(:habit, user: user, created_at: 5.days.ago)
    h2 = create(:habit, user: user, created_at: 5.days.ago)
    [ h1, h2 ].each { |h| h.habit_logs.create!(date: 1.day.ago.to_date, completed: true) }

    chain = described_class.new(user, days: 3, trim: false).to_a
    yesterday = chain.find { |e| e[:date] == 1.day.ago.to_date }
    expect(yesterday[:status]).to eq(:perfect)
    expect(yesterday[:possible]).to eq(2)
    expect(yesterday[:completed]).to eq(2)
  end

  it "is :partial when some but not all active habits are completed" do
    h1 = create(:habit, user: user, created_at: 5.days.ago)
    create(:habit, user: user, created_at: 5.days.ago)
    h1.habit_logs.create!(date: 1.day.ago.to_date, completed: true)

    chain = described_class.new(user, days: 3, trim: false).to_a
    yesterday = chain.find { |e| e[:date] == 1.day.ago.to_date }
    expect(yesterday[:status]).to eq(:partial)
  end

  it "is :missed when active habits exist but none completed" do
    create(:habit, user: user, created_at: 5.days.ago)
    chain = described_class.new(user, days: 3, trim: false).to_a
    yesterday = chain.find { |e| e[:date] == 1.day.ago.to_date }
    expect(yesterday[:status]).to eq(:missed)
  end

  it "ignores habits created after a day (they are not active yet)" do
    h_new = create(:habit, user: user, created_at: 2.hours.ago)
    h_new.habit_logs.create!(date: 5.days.ago.to_date, completed: true)
    chain = described_class.new(user, days: 7, trim: false).to_a
    # 5 days ago: habit didn't exist → no_habits.
    five_days_ago = chain.find { |e| e[:date] == 5.days.ago.to_date }
    expect(five_days_ago[:status]).to eq(:no_habits)
  end

  it "ignores archived habits on/after their archive day" do
    h = create(:habit, user: user, created_at: 10.days.ago, archived_at: 2.days.ago)
    h.habit_logs.create!(date: 3.days.ago.to_date, completed: true)
    chain = described_class.new(user, days: 5, trim: false).to_a
    # 3 days ago: active + completed → perfect; 1 day ago: archived → no_habits.
    three = chain.find { |e| e[:date] == 3.days.ago.to_date }
    one = chain.find { |e| e[:date] == 1.day.ago.to_date }
    expect(three[:status]).to eq(:perfect)
    expect(one[:status]).to eq(:no_habits)
  end

  it "ignores weekly and monthly habits — only daily habits count toward perfect days" do
    daily = create(:habit, user: user, frequency: "daily",   created_at: 10.days.ago)
    create(:habit,        user: user, frequency: "weekly",  created_at: 10.days.ago)
    create(:habit,        user: user, frequency: "monthly", created_at: 10.days.ago)
    daily.habit_logs.create!(date: 1.day.ago.to_date, completed: true)

    chain = described_class.new(user, days: 3, trim: false).to_a
    yesterday = chain.find { |e| e[:date] == 1.day.ago.to_date }
    # Daily habit done, weekly/monthly ignored → perfect.
    expect(yesterday[:status]).to eq(:perfect)
    expect(yesterday[:possible]).to eq(1)
  end

  describe "trimming" do
    it "trims leading days until the first perfect or partial entry" do
      h = create(:habit, user: user, created_at: 10.days.ago)
      h.habit_logs.create!(date: 3.days.ago.to_date, completed: true) # first perfect

      chain = described_class.new(user, days: 7).to_a
      expect(chain.first[:date]).to eq(3.days.ago.to_date)
      expect(chain.first[:status]).to eq(:perfect)
      expect(chain.size).to eq(4) # 3d ago → today
    end

    it "collapses to a single today entry when nothing positive happened in the window" do
      create(:habit, user: user, created_at: 5.days.ago) # no logs anywhere
      chain = described_class.new(user, days: 7).to_a
      expect(chain.size).to eq(1)
      expect(chain.first[:date]).to eq(Date.current)
    end
  end

  describe "#current_perfect_streak" do
    it "counts consecutive perfect days back from today" do
      h = create(:habit, user: user, created_at: 5.days.ago)
      [ 0, 1, 2 ].each { |i| h.habit_logs.create!(date: i.days.ago.to_date, completed: true) }
      expect(described_class.new(user, days: 7).current_perfect_streak).to eq(3)
    end

    it "skips an in-progress today (counts yesterday backwards) when today is not perfect" do
      h = create(:habit, user: user, created_at: 5.days.ago)
      [ 1, 2 ].each { |i| h.habit_logs.create!(date: i.days.ago.to_date, completed: true) }
      # Today has no log → missed, but we should still count yesterday + day-before-yesterday.
      expect(described_class.new(user, days: 7).current_perfect_streak).to eq(2)
    end

    it "treats :no_habits days as neutral pass-through, not a reset" do
      h = create(:habit, user: user, created_at: 1.day.ago)
      h.habit_logs.create!(date: Date.current, completed: true)
      # 7-day window: today is perfect, prior days are :no_habits.
      expect(described_class.new(user, days: 7, trim: false).current_perfect_streak).to eq(1)
    end
  end
end
