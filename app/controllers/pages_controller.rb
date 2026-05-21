class PagesController < ApplicationController
  def home
    today = Date.current

    @month_net_cents = current_user.transactions.this_month.income.sum(:amount_cents) -
                       current_user.transactions.this_month.expense.sum(:amount_cents)
    @active_streaks  = current_user.habits.active.count { |h| h.current_streak.positive? }
    @open_todos      = current_user.todos.open.count
    @today_events    = current_user.events.where(start_at: today.all_day).count

    @today_habits      = current_user.habits.active.order(:name).limit(6)
    @upcoming_todos    = current_user.todos.open.where("due_at <= ?", 7.days.from_now).order(:due_at).limit(6)
    @today_events_list = current_user.events.where(start_at: today.all_day).order(:start_at).limit(4)
    @active_goals      = current_user.goals.active.ordered.limit(3)

    # Build a 7-day spending series with string-keyed labels so Chart.js
    # uses a category axis (no date-adapter dependency required).
    spending_by_date = current_user.transactions.expense
                                   .where(date: 6.days.ago.to_date..today)
                                   .group(:date).sum(:amount_cents)
    @spending_series = (0..6).each_with_object({}) do |offset, h|
      d = 6.days.ago.to_date + offset.days
      h[I18n.l(d, format: "%d %b")] = spending_by_date[d] || 0
    end

    week_start = today.beginning_of_week
    @habit_completion_pct = if current_user.habits.active.any?
                              completed = current_user.habit_logs.where(completed: true, date: week_start..today).count
                              possible  = current_user.habits.active.count * (today - week_start + 1).to_i
                              possible.zero? ? 0 : (completed.to_f / possible * 100).round
    else
                              0
    end

    @currency = current_user.currency
  end
end
