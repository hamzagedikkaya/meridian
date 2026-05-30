# Builds the "Perfect Days" chain for a user — a day is perfect when every
# habit that was active on that day was completed. Computes the window in two
# queries (one for habits with their created/archived bounds, one for daily
# completed-log counts) regardless of habit count.
#
# Returned by #to_a as an array of hashes, oldest → newest:
#
#   [{ date:, status: :perfect|:partial|:missed|:no_habits, completed:, possible: }, ...]
#
#   :perfect    — every active habit on this day was completed
#   :partial    — at least one but not all active habits completed
#   :missed     — habits were active but none completed
#   :no_habits  — no habits were active on this day; does NOT break the streak
class PerfectDayChain
  DEFAULT_COLOR = "#B8860B".freeze

  def initialize(user, days: 30, end_date: Date.current, color: DEFAULT_COLOR)
    @user = user
    @days = days
    @end_date = end_date
    @color = color
    @range = (end_date - (days - 1).days)..end_date
  end

  def to_a
    @to_a ||= build
  end

  def current_perfect_streak
    perfect_streak_from(to_a.reverse)
  end

  def longest_perfect_streak
    longest = current = 0
    to_a.each do |day|
      if day[:status] == :perfect || day[:status] == :no_habits
        current += day[:status] == :perfect ? 1 : 0
        longest = current if current > longest
      else
        current = 0
      end
    end
    longest
  end

  private

  attr_reader :user, :days, :end_date, :color, :range

  def build
    # Only daily habits count toward "perfect days" — weekly/monthly aren't
    # expected on every day, so a missed Friday gym shouldn't reset 6 perfect
    # daily days. Periodic habits get their own status widget elsewhere.
    habits_meta = user.habits.where(frequency: "daily").pluck(:created_at, :archived_at).map do |created_at, archived_at|
      { created_on: created_at.to_date, archived_on: archived_at&.to_date }
    end
    completed_per_day = user.habit_logs.joins(:habit)
                            .where(habits: { frequency: "daily" }, completed: true, date: range)
                            .group(:date).count

    range.map do |date|
      active = habits_meta.count { |h| habit_active_on?(h, date) }
      completed = completed_per_day[date].to_i
      { date: date, status: classify(active, completed), completed: completed, possible: active, color: color }
    end
  end

  def habit_active_on?(habit_meta, date)
    return false if habit_meta[:created_on] > date
    return false if habit_meta[:archived_on] && habit_meta[:archived_on] <= date
    true
  end

  def classify(active, completed)
    return :no_habits if active.zero?
    return :perfect   if completed >= active
    return :missed    if completed.zero?
    :partial
  end

  # Walks newest → oldest, counting consecutive :perfect days. :no_habits is
  # a neutral pass-through (doesn't add, doesn't reset). If today is not yet
  # perfect, it is skipped (so an in-progress day doesn't reset the streak —
  # matches Habit#current_streak's today/yesterday cutoff behaviour).
  def perfect_streak_from(reversed)
    streak = 0
    reversed.each_with_index do |day, idx|
      first_day_not_perfect = idx.zero? && day[:date] == end_date && day[:status] != :perfect
      next if first_day_not_perfect
      case day[:status]
      when :perfect    then streak += 1
      when :no_habits  then next
      else                  break
      end
    end
    streak
  end
end
