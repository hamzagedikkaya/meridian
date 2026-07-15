module Api
  module V1
    class HabitsController < BaseController
      before_action :set_habit, only: [ :show, :update, :toggle_today, :archive ]

      def index
        habits = active_habits
        streaks = Habit.streaks_for(habits)
        chains = Habit.chain_windows_for(habits, days: 14, trim: false)
        today_logs = today_logs_for(habits)

        render json: {
          habits: habits.map do |habit|
            habit_json(habit,
              streak: streaks[habit.id],
              chain: chains[habit],
              today_log: today_logs[habit.id] || habit.habit_logs.new(date: Date.current))
          end,
          meta: meta_json(habits, today_logs)
        }
      end

      def show
        days = params[:days].to_i
        days = 30 unless days.between?(1, 366)
        render json: { habit: habit_json(@habit, chain: @habit.chain_window(days: days, trim: false)) }
      end

      def create
        habit = current_user.habits.new(habit_attributes)
        if habit.save
          render json: { habit: habit_json(habit) }, status: :created
        else
          render_errors(habit)
        end
      end

      def update
        if @habit.update(habit_attributes)
          render json: { habit: habit_json(@habit) }
        else
          render_errors(@habit)
        end
      end

      def toggle_today
        log = @habit.log_for(Date.current)

        if params[:delta].present? && @habit.target_count > 1
          log.count = (log.count.to_i + params[:delta].to_i).clamp(0, @habit.target_count)
          log.completed = log.count >= @habit.target_count
        else
          log.completed = !log.completed
          log.count = log.completed ? @habit.target_count : 0
        end
        log.save!

        habits = active_habits
        today_logs = today_logs_for(habits)
        render json: {
          habit: habit_json(@habit, today_log: today_logs[@habit.id]),
          meta: meta_json(habits, today_logs)
        }
      end

      def archive
        @habit.update!(archived_at: Time.current)
        render json: { habit: habit_json(@habit) }
      end

      private

      def set_habit
        @habit = current_user.habits.find(params[:id])
      end

      def active_habits
        current_user.habits.active.order(:name)
      end

      def today_logs_for(habits)
        HabitLog.where(habit_id: habits.map(&:id), date: Date.current).index_by(&:habit_id)
      end

      def habit_attributes
        attrs = params.permit(:name, :description, :frequency, :target_count, :color, :goal_id)
        attrs[:goal_id] = current_user.goals.find(attrs[:goal_id]).id if attrs[:goal_id].present?
        attrs
      end

      def habit_json(habit, streak: nil, chain: nil, today_log: nil)
        Serialize.habit(
          habit,
          streak: streak || habit.current_streak,
          chain: chain_json(chain || habit.chain_window(days: 14, trim: false)),
          today_log: today_log
        )
      end

      def chain_json(entries)
        entries.map { |entry| entry.slice(:date, :status, :completed, :possible) }
      end

      def meta_json(habits, today_logs)
        perfect = PerfectDayChain.new(current_user, days: 30)
        {
          completed_today: today_logs.values.count(&:completed?),
          total_active: habits.size,
          perfect_day: {
            chain: perfect.to_a.map { |entry| entry.slice(:date, :status) },
            current_streak: perfect.current_perfect_streak,
            longest_streak: perfect.longest_perfect_streak
          }
        }
      end
    end
  end
end
