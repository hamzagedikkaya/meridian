class Habit < ApplicationRecord
  FREQUENCIES = %w[daily weekly monthly].freeze

  belongs_to :user
  has_many :habit_logs, dependent: :destroy

  validates :name, presence: true, length: { maximum: 60 }
  validates :frequency, inclusion: { in: FREQUENCIES }
  validates :target_count, numericality: { greater_than: 0 }

  scope :active, -> { where(archived_at: nil) }

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
end
