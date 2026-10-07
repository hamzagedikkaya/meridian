class HabitsController < ApplicationController
  before_action :set_habit, only: [ :show, :edit, :update, :destroy, :toggle_today ]

  def index
    @habits = current_user.habits.active.includes(:habit_logs).order(:name)
    @habit_chains = Habit.chain_windows_for(@habits, days: 14)
    @periodic_habits = @habits.reject { |h| h.frequency == "daily" }

    perfect_chain_service = PerfectDayChain.new(current_user, days: 30)
    @perfect_day_chain    = perfect_chain_service.to_a
    @perfect_streak       = perfect_chain_service.current_perfect_streak
    @longest_perfect      = perfect_chain_service.longest_perfect_streak
  end

  def show
  end

  def new
    @habit = current_user.habits.new(name: prefill_name, frequency: "daily", target_count: 1, color: "#B8860B")
  end

  def create
    @habit = current_user.habits.new(habit_params)
    if @habit.save
      redirect_to habits_path, notice: t("flash.saved")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @habit.update(habit_params)
      redirect_to habits_path, notice: t("flash.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @habit.destroy
    redirect_to habits_path, notice: t("flash.deleted")
  end

  def toggle_today
    # +/- counter mode when a delta comes from the inline counter widget;
    # otherwise a plain checkbox flip. Rules live in Habit#toggle_log!, shared
    # with the API, which also refuses an archived habit.
    delta = params[:delta]
    @habit.toggle_log!(Date.current, delta: delta.is_a?(String) ? delta.presence&.to_i : nil)

    respond_to do |format|
      format.turbo_stream { render turbo_stream: toggle_today_streams }
      format.html         { redirect_back fallback_location: habits_path }
    end
  rescue Habit::LogRefused
    redirect_back fallback_location: habits_path, alert: t("api.errors.habit_archived"), status: :see_other
  end

  private

  def set_habit
    @habit = current_user.habits.find(params[:id])
  end

  # Quick capture links here with habit[name] when "habit: X" names a habit
  # that does not exist yet.
  def prefill_name
    habit = params[:habit]
    name = habit[:name] if habit.is_a?(ActionController::Parameters)
    name if name.is_a?(String)
  end

  def habit_params
    params.require(:habit).permit(:name, :description, :frequency, :target_count, :color, :archived_at)
  end

  # Builds the turbo-stream replacements for a toggle: the toggled row, the
  # global perfect-day widget, the today-progress card, and the dashboard
  # row partial. Targets missing on the current page are silently ignored.
  def toggle_today_streams
    habits = current_user.habits.active.includes(:habit_logs).order(:name)
    service = PerfectDayChain.new(current_user, days: 30)
    completed_today = habits.count { |h| h.completed_on?(Date.current) }

    [
      turbo_stream.replace(helpers.dom_id(@habit, :index_row),
        partial: "habits/index_row",
        locals: { habit: @habit, chain: @habit.chain_window(days: 14) }),
      turbo_stream.replace(helpers.dom_id(@habit, :dashboard),
        partial: "pages/dashboard_habit",
        locals: { habit: @habit }),
      turbo_stream.replace("perfect_day_widget",
        partial: "habits/perfect_day_widget",
        locals: {
          perfect_day_chain: service.to_a,
          perfect_streak: service.current_perfect_streak,
          longest_perfect: service.longest_perfect_streak
        }),
      turbo_stream.replace("habits_today_progress",
        partial: "habits/today_progress",
        locals: { habits: habits, completed_today: completed_today })
    ]
  end
end
