class Habit < ApplicationRecord
  FREQUENCIES = %w[daily weekly monthly].freeze

  belongs_to :user
  belongs_to :goal, optional: true
  has_many :habit_logs, dependent: :destroy

  validates :name, presence: true, length: { maximum: 60 }
  validates :frequency, inclusion: { in: FREQUENCIES }
  validates :target_count, numericality: { greater_than: 0 }

  scope :active, -> { where(archived_at: nil) }

  # Batched streak calculation — one query for many habits instead of N.
  def self.streaks_for(habits)
    habit_ids = habits.map(&:id)
    return {} if habit_ids.empty?

    today = Date.current
    rows = HabitLog.where(habit_id: habit_ids, completed: true, date: ..today)
                   .order(date: :desc).pluck(:habit_id, :date)
    by_habit = rows.group_by(&:first).transform_values { |arr| arr.map(&:last) }

    habit_ids.index_with do |hid|
      dates = by_habit[hid] || []
      cutoff = dates.include?(today) ? today : today - 1.day
      relevant = dates.drop_while { |d| d > cutoff }
      next 0 if relevant.empty? || relevant.first != cutoff

      streak = 1
      relevant.each_cons(2) do |a, b|
        (a - b).to_i == 1 ? streak += 1 : break
      end
      streak
    end
  end

  def log_for(date)
    habit_logs.find_or_initialize_by(date: date)
  end

  def completed_on?(date)
    habit_logs.where(date: date, completed: true).exists?
  end

  # Returns the current streak — consecutive days ending today (or yesterday if today not yet logged).
  def current_streak
    cutoff = completed_on?(Date.current) ? Date.current : Date.current - 1.day
    completed_dates = habit_logs.where(completed: true).where(date: ..cutoff).order(date: :desc).pluck(:date)
    return 0 if completed_dates.empty? || completed_dates.first != cutoff

    streak = 1
    completed_dates.each_cons(2) do |a, b|
      if (a - b).to_i == 1
        streak += 1
      else
        break
      end
    end
    streak
  end

  def longest_streak
    dates = habit_logs.where(completed: true).order(:date).pluck(:date)
    return 0 if dates.empty?

    longest = current = 1
    dates.each_cons(2) do |a, b|
      if (b - a).to_i == 1
        current += 1
        longest = current if current > longest
      else
        current = 1
      end
    end
    longest
  end

  def completion_rate(days: 30)
    range = (Date.current - days.days + 1.day)..Date.current
    completed = habit_logs.where(completed: true, date: range).count
    (completed.to_f / days * 100).round(1)
  end

  # Number of completed logs in the habit's current period — week for weekly
  # habits, month for monthly, the single day for daily. Used by the periodic
  # habits widget on /habits.
  def period_completed_count(today = Date.current)
    habit_logs.where(completed: true, date: period_range(today)).count
  end

  def period_complete?(today = Date.current)
    period_completed_count(today) >= target_count
  end

  def period_range(today = Date.current)
    case frequency
    when "weekly"  then today.beginning_of_week..today.end_of_week
    when "monthly" then today.beginning_of_month..today.end_of_month
    else                today..today
    end
  end

  # Returns the last `days` daily statuses for the "don't break the chain"
  # visualisation. Each element is `{ date:, status:, color: }` where status is
  # one of :completed, :missed, :today_pending. Oldest first → newest last,
  # length always == days.
  def chain_window(days: 30, end_date: Date.current)
    range = (end_date - (days - 1).days)..end_date
    by_date = habit_logs.where(date: range).index_by(&:date)
    range.map { |d| { date: d, status: chain_status_for(d, by_date[d], end_date), color: color } }
  end

  # Batched chain window for the index page — one HabitLog query covering all
  # habits in the given window, then bucketed in memory.
  def self.chain_windows_for(habits, days: 14, end_date: Date.current)
    return {} if habits.empty?

    range = (end_date - (days - 1).days)..end_date
    rows = HabitLog.where(habit_id: habits.map(&:id), date: range)
    by_habit = rows.group_by(&:habit_id).transform_values { |logs| logs.index_by(&:date) }

    habits.index_with do |habit|
      bucket = by_habit[habit.id] || {}
      range.map { |d| { date: d, status: habit.send(:chain_status_for, d, bucket[d], end_date), color: habit.color } }
    end
  end

  private

  def chain_status_for(date, log, end_date)
    if log&.completed
      :completed
    elsif date == Date.current && date == end_date
      :today_pending
    else
      :missed
    end
  end
end
