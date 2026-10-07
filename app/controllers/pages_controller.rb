class PagesController < ApplicationController
  def home
    today = Date.current

    @month_net_cents = current_user.transactions.this_month.income.sum(:amount_cents) -
                       current_user.transactions.this_month.expense.sum(:amount_cents)
    @active_streaks  = current_user.habits.active.count { |h| h.current_streak.positive? }
    @open_todos      = current_user.todos.open.count
    # Recurring series show on the days they occur, as in GET /api/v1/home
    # and the calendar (Event.occurrences_by_event).
    week_events = Event.occurrences_by_event(current_user.events.order(:start_at), 6.days.ago.to_date, today)
    todays_events = week_events.select { |_, dates| dates.include?(today) }.map(&:first)
    @today_events    = todays_events.size

    @today_habits      = current_user.habits.active.order(:name).limit(6)
    @upcoming_todos    = current_user.todos.open.where("due_at <= ?", 7.days.from_now).order(:due_at).limit(6)
    @today_events_list = todays_events.first(4)
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

    @habit_completion_pct = Habit.week_completion_pct(current_user.habits.active.to_a, today)

    @currency = current_user.currency

    # 7-day sparkline series for the stat cards.
    range_7d = (6.days.ago.to_date..today).to_a
    income_by_day  = current_user.transactions.income.where(date: range_7d).group(:date).sum(:amount_cents)
    expense_by_day = current_user.transactions.expense.where(date: range_7d).group(:date).sum(:amount_cents)
    habit_logs_by_day = current_user.habit_logs.where(completed: true, date: range_7d).group(:date).count
    # Bucketed by day in the request's zone, like the window itself; SQL
    # DATE() would bucket by the UTC date.
    todos_done_by_day = current_user.todos.where(status: "done", completed_at: range_7d.first.beginning_of_day..range_7d.last.end_of_day)
                                   .group_by_day(:completed_at).count
    events_by_day     = week_events.flat_map(&:last).tally

    @sparkline_net    = range_7d.map { |d| ((income_by_day[d] || 0) - (expense_by_day[d] || 0)) / 100.0 }
    @sparkline_habits = range_7d.map { |d| habit_logs_by_day[d] || 0 }
    @sparkline_todos  = range_7d.map { |d| todos_done_by_day[d] || 0 }
    @sparkline_events = range_7d.map { |d| events_by_day[d] || 0 }
  end
end
