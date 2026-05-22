class InsightsController < ApplicationController
  def index
    @range_days = (params[:days] || 30).to_i
    from = @range_days.days.ago.to_date
    to   = Date.current

    # Weekend vs weekday spending
    weekend_spend = current_user.transactions.expense.between(from, to)
                                 .where("EXTRACT(DOW FROM date) IN (0, 6)").sum(:amount_cents)
    weekday_spend = current_user.transactions.expense.between(from, to)
                                 .where("EXTRACT(DOW FROM date) NOT IN (0, 6)").sum(:amount_cents)
    weekend_days = (from..to).count { |d| d.saturday? || d.sunday? }
    weekday_days = (from..to).count - weekend_days
    @weekend_avg = weekend_days.zero? ? 0 : weekend_spend / weekend_days
    @weekday_avg = weekday_days.zero? ? 0 : weekday_spend / weekday_days

    # Habit streaks distribution
    active_habits = current_user.habits.active.to_a
    streaks = Habit.streaks_for(active_habits)
    @habit_streaks = active_habits.map { |h| [ h.name, streaks[h.id] ] }
                                  .sort_by { |(_, s)| -s }

    # Mood vs habit completion (last 30 days)
    @mood_completion = mood_completion_correlation(from, to)

    # Focus day-of-week breakdown
    @focus_by_dow = current_user.focus_sessions.completed.where(started_at: from..to.end_of_day)
                                 .group_by_day_of_week(:started_at, format: "%a").sum(:duration_seconds)
                                 .transform_values { |s| s / 60 }

    # Top spending categories
    @top_categories = current_user.transactions.expense.between(from, to)
                                   .joins(:finance_category)
                                   .group("finance_categories.name")
                                   .sum(:amount_cents)
                                   .sort_by { |_, v| -v }
                                   .first(8)

    # Productivity: todos completed vs created per week
    @todo_weekly = todo_weekly_breakdown(from, to)
  end

  private

  def mood_completion_correlation(from, to)
    entries = current_user.journal_entries.where(date: from..to).where.not(mood: nil)
    return [] if entries.empty?

    by_mood = Hash.new { |h, k| h[k] = { count: 0, completed_days: 0, total_days: 0 } }
    entries.each do |entry|
      by_mood[entry.mood][:count] += 1
      logs = current_user.habit_logs.where(date: entry.date)
      by_mood[entry.mood][:completed_days] += logs.where(completed: true).count
      by_mood[entry.mood][:total_days]     += logs.count
    end

    by_mood.map { |mood, stats|
      rate = stats[:total_days].zero? ? 0 : (stats[:completed_days].to_f / stats[:total_days] * 100).round
      { mood: mood, emoji: JournalEntry::MOOD_EMOJI[mood], days: stats[:count], rate: rate }
    }
  end

  def todo_weekly_breakdown(from, to)
    completed = current_user.todos.where(status: "done")
                             .where(completed_at: from.beginning_of_day..to.end_of_day)
                             .group_by_week(:completed_at, format: "%d %b").count
    created = current_user.todos.where(created_at: from.beginning_of_day..to.end_of_day)
                           .group_by_week(:created_at, format: "%d %b").count

    weeks = (completed.keys + created.keys).uniq.sort
    weeks.map { |w| { week: w, completed: completed[w] || 0, created: created[w] || 0 } }
  end
end
