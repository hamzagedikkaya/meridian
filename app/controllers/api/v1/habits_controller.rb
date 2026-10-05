module Api
  module V1
    class HabitsController < BaseController
      LIST_CHAIN_DAYS = 14

      before_action :set_habit, only: [ :show, :update, :destroy, :toggle_today, :update_log, :archive, :unarchive ]

      # Active habits by name (unchanged). archived=true lists the archived
      # ones instead, most recently archived first, each with its chain
      # ending on the day it was archived. meta always describes the active
      # habits.
      def index
        archived = boolean_param(:archived)
        active = active_habits.to_a
        habits = archived ? current_user.habits.archived.order(archived_at: :desc, id: :desc).to_a : active
        chains = archived ? archived_chains(habits) : Habit.chain_windows_for(habits, days: LIST_CHAIN_DAYS, trim: false)
        streaks = streaks_for(habits)
        today_logs = today_logs_for(habits)

        render json: {
          habits: habits.map do |habit|
            habit_json(habit,
              streak: streaks.fetch(habit.id, 0),
              chain: chains[habit],
              today_log: today_logs[habit.id] || habit.habit_logs.new(date: Date.current))
          end,
          meta: meta_json(active, archived ? today_logs_for(active) : today_logs)
        }
      end

      # Archived habits open too. Adds what an archive or delete confirmation
      # needs: how many days were logged, and which goals count this habit.
      def show
        chain = @habit.chain_window(days: chain_days(lenient_integer_param(:days), 30), end_date: @habit.last_active_date, trim: false)
        render json: { habit: habit_json(@habit, chain: chain).merge(detail_json(@habit)) }
      end

      def create
        habit = current_user.habits.new
        habit.assign_attributes(habit_attributes)
        if save_checked(habit) { check_color(habit) }
          render json: { habit: habit_json(habit) }, status: :created
        else
          render_errors(habit)
        end
      end

      # Only the keys sent change.
      def update
        @habit.assign_attributes(habit_attributes)
        if save_checked(@habit) { check_color(@habit) }
          render json: { habit: habit_json(@habit) }
        else
          render_errors(@habit)
        end
      end

      # As on the web, the habit's logs go with it, so its streaks and its
      # days in the perfect-day history disappear. Habit goals that counted
      # it are unlinked and keep its final count (Habit#tracking_goals); the
      # goal it served (goal_id) is not touched.
      def destroy
        @habit.destroy!
        head :no_content
      end

      # Flips today's log, or moves the counter by `delta` for habits with
      # target_count > 1. Kept for older clients; PUT logs/:date sets an
      # explicit state and is safe to retry. Archived habits are refused, as
      # by PUT logs/:date.
      def toggle_today
        return render_log_refusal(:habit_archived) if @habit.archived?

        # delta only moves a counter (target_count > 1); otherwise it is not read.
        delta = lenient_integer_param(:delta) if @habit.target_count > 1
        @habit.toggle_log!(Date.current, delta: delta)
        render_habit_change
      end

      # PUT /api/v1/habits/:id/logs/:date
      # Sets the log for one day (today or earlier, never the future) to an
      # explicit count; count 0 removes it. `completed` is shorthand for
      # count = target_count / 0. Same request twice, same state.
      #
      # Every parameter is read and checked before the write, so an error
      # response never leaves a changed log behind.
      def update_log
        date = date_param(:date)
        count = requested_log_count
        days = chain_days(integer_param(:days), LIST_CHAIN_DAYS)
        refusal = @habit.log_refusal(date)
        return render_log_refusal(refusal) if refusal

        log = @habit.set_log_count!(date, count)
        render_habit_change(log: log, chain_days: days)
      end

      # Hides the habit from the active list, Today and quick capture, and
      # freezes its logs. Idempotent: archiving an archived habit keeps its
      # first archived_at.
      def archive
        @habit.update!(archived_at: Time.current) unless @habit.archived?
        render json: { habit: habit_json(@habit) }
      end

      # Back in the active list, loggable again. Idempotent.
      def unarchive
        @habit.update!(archived_at: nil) if @habit.archived?
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

      # Each archived habit's chain ends on its own archive day, so it shows
      # the habit's last days in use rather than the days since. One log
      # query for all of them.
      def archived_chains(habits)
        Habit.chain_windows_for(habits, days: LIST_CHAIN_DAYS, end_date: ->(habit) { habit.last_active_date }, trim: false)
      end

      # A streak runs up to today or yesterday, and an archived habit's logs
      # stop on its archive day, so only one archived since yesterday can
      # have one; the others are 0 without reading their logs.
      def streaks_for(habits)
        Habit.streaks_for(habits.select { |habit| habit.last_active_date >= Date.yesterday })
      end

      # Length of the returned chain: `days` when it is within 1..366,
      # otherwise the default.
      def chain_days(days, default)
        days&.between?(1, 366) ? days : default
      end

      # `count` wins over `completed`; one of them is required.
      def requested_log_count
        count = integer_param(:count)
        raise InvalidParameter, :count if count&.negative?
        return count if count

        completed = boolean_param(:completed)
        raise InvalidParameter, :count if completed.nil?

        completed ? @habit.target_count : 0
      end

      # The 422 for a Habit#log_refusal code.
      def render_log_refusal(code)
        case code
        when :habit_archived
          render_unprocessable(:habit_archived, message: I18n.t("api.errors.habit_archived"))
        when :future_date
          render_unprocessable(:future_date, field: :date, message: I18n.t("api.errors.future_date"))
        when :before_habit_start
          render_unprocessable(:before_habit_start, field: :date,
            message: I18n.t("api.errors.before_habit_start", date: I18n.l(@habit.start_date, format: :long)),
            habit_start: @habit.start_date)
        end
      end

      # The habit as GET /habits lists it, so the client can merge it in place,
      # plus the header meta toggle_today has always returned.
      def render_habit_change(log: nil, chain_days: LIST_CHAIN_DAYS)
        habits = active_habits
        today_logs = today_logs_for(habits)
        json = {
          habit: habit_json(@habit,
            chain: @habit.chain_window(days: chain_days, trim: false),
            today_log: today_logs[@habit.id]),
          meta: meta_json(habits, today_logs)
        }
        json[:log] = { date: log.date, count: log.count, completed: log.completed } if log
        render json: json
      end

      # The web form's fields (HabitsController#habit_params; archived_at is
      # set by archive/unarchive instead) plus goal_id, the goal the habit
      # serves: one of the user's goals (404 otherwise), or null to unlink.
      # Only the keys sent are returned.
      def habit_attributes
        attrs = params.permit(:name, :description, :frequency, :color).to_h
        attrs[:target_count] = integer_param(:target_count) if params.key?(:target_count)
        attrs[:goal_id] = owned_id_param(current_user.goals, :goal_id) if params.key?(:goal_id)
        attrs
      end

      def habit_json(habit, streak: nil, chain: nil, today_log: nil)
        Serialize.habit(
          habit,
          streak: streak || habit.current_streak,
          chain: chain_json(chain || habit.chain_window(days: LIST_CHAIN_DAYS, end_date: habit.last_active_date, trim: false)),
          today_log: today_log
        )
      end

      def chain_json(entries)
        entries.map { |entry| entry.slice(:date, :status, :completed, :possible) }
      end

      # Logged days: days with a count above 0 (what a delete removes).
      # Completed days: what a habit goal counts.
      def detail_json(habit)
        logs = habit.habit_logs
        counts = logs.where(count: 1..).or(logs.where(completed: true)).group(:completed).count
        {
          logged_days_count: counts.values.sum,
          completed_days_count: counts[true] || 0,
          tracked_by_goals: habit.tracking_goals.where(user_id: current_user.id).ordered
                                 .map { |goal| { id: goal.id, name: goal.name, status: goal.status } }
        }
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
