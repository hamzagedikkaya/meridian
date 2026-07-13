module Api
  module V1
    class HomeController < BaseController
      def show
        today = Date.current
        habits = current_user.habits.active.order(:name).to_a
        streaks = Habit.streaks_for(habits)
        today_logs = HabitLog.where(habit_id: habits.map(&:id), date: today).index_by(&:habit_id)
        events = today_events(today)
        perfect = PerfectDayChain.new(current_user, days: 30)

        render json: {
          currency: current_user.currency,
          subunit_to_unit: Serialize.subunit_to_unit(current_user.currency),
          month_net_cents: month_net_cents,
          active_streaks: streaks.values.count(&:positive?),
          open_todos: current_user.todos.open.count,
          overdue_count: current_user.todos.overdue.count,
          today_events_count: events.size,
          habit_completion_pct: habit_completion_pct(habits.size, today),
          spending_7d: spending_7d(today),
          today_habits: habits.map { |habit| today_habit_json(habit, streaks[habit.id], today_logs[habit.id]) },
          upcoming_todos: upcoming_todos.map { |todo| Serialize.todo(todo) },
          today_events: events.first(4).map { |event| Serialize.event(event) },
          active_goals: active_goals_json,
          perfect_day: {
            chain: perfect.to_a.map { |day| { date: day[:date], status: day[:status] } },
            current_streak: perfect.current_perfect_streak
          }
        }
      end

      private

      def month_net_cents
        current_user.transactions.this_month.income.sum(:amount_cents) -
          current_user.transactions.this_month.expense.sum(:amount_cents)
      end

      # Week-to-date completion: completed logs / (active habits × days elapsed).
      def habit_completion_pct(active_count, today)
        return 0 if active_count.zero?

        week_start = today.beginning_of_week
        completed = current_user.habit_logs.where(completed: true, date: week_start..today).count
        possible = active_count * (today - week_start + 1).to_i
        (completed.to_f / possible * 100).round
      end

      def spending_7d(today)
        window = (today - 6.days)..today
        by_date = current_user.transactions.expense.where(date: window).group(:date).sum(:amount_cents)
        window.map { |date| { date: date, cents: by_date[date] || 0 } }
      end

      def today_habit_json(habit, streak, log)
        {
          id: habit.id,
          name: habit.name,
          color: habit.color,
          target_count: habit.target_count,
          completed_today: log.present? && log.completed?,
          today_count: log&.count.to_i,
          current_streak: streak
        }
      end

      def upcoming_todos
        current_user.todos.open
                    .where(due_at: ..7.days.from_now)
                    .includes(:todo_list, :subtasks)
                    .order(:due_at)
                    .limit(6)
      end

      # Recurring events materialize into today via occurrences_between, like
      # the web calendar grid.
      def today_events(today)
        current_user.events.where(start_at: today.all_day)
                    .or(current_user.events.recurring.where(start_at: ..today.end_of_day))
                    .order(:start_at)
                    .select { |event| event.occurrences_between(today.beginning_of_day, today.end_of_day).include?(today) }
      end

      def active_goals_json
        current_user.goals.active.ordered.limit(3).map do |goal|
          { id: goal.id, name: goal.name, color: goal.color, progress_percent: goal.progress_percent }
        end
      end
    end
  end
end
