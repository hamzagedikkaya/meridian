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
          # The user's local date the rest of this payload is computed for.
          today: today,
          currency: current_user.currency,
          subunit_to_unit: Serialize.subunit_to_unit(current_user.currency),
          month_net_cents: month_net_cents,
          active_streaks: streaks.values.count(&:positive?),
          open_todos: current_user.todos.open.count,
          overdue_count: current_user.todos.overdue.count,
          today_events_count: events.size,
          habit_completion_pct: Habit.week_completion_pct(habits, today),
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

      # Recurring events materialize into today, as in the web dashboard and
      # calendar (Event.occurrences_by_event).
      def today_events(today)
        Event.occurrences_by_event(current_user.events.order(:start_at), today, today).map(&:first)
      end

      # Recomputed as GET /goals recomputes them, so the card shows current
      # progress, and a goal that reached its target since (a transaction, a
      # habit log) is no longer listed as active.
      def active_goals_json
        goals = current_user.goals.where.not(status: "abandoned").includes(:related, :user).ordered.to_a
        goals.each(&:recalculate_progress!)
        goals.select { |goal| goal.status == "active" }.first(3).map do |goal|
          { id: goal.id, name: goal.name, color: goal.color, progress_percent: goal.progress_percent }
        end
      end
    end
  end
end
