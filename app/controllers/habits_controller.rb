class HabitsController < ApplicationController
  before_action :set_habit, only: [ :show, :edit, :update, :destroy, :toggle_today ]

  def index
    @habits = current_user.habits.active.includes(:habit_logs).order(:name)
    @habit_chains = Habit.chain_windows_for(@habits, days: 14)

    perfect_chain_service = PerfectDayChain.new(current_user, days: 30)
    @perfect_day_chain    = perfect_chain_service.to_a
    @perfect_streak       = perfect_chain_service.current_perfect_streak
    @longest_perfect      = perfect_chain_service.longest_perfect_streak
  end

  def show
  end

  def new
    @habit = current_user.habits.new(frequency: "daily", target_count: 1, color: "#B8860B")
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
    log = @habit.log_for(Date.current)

    if params[:delta].present? && @habit.target_count > 1
      # +/- counter mode (from the inline counter widget).
      delta = params[:delta].to_i
      log.count = (log.count.to_i + delta).clamp(0, @habit.target_count)
      log.completed = log.count >= @habit.target_count
    else
      # Plain checkbox toggle — universal. For multi-count habits this jumps
      # straight to "all done" (count = target_count) or "reset" (count = 0).
      log.completed = !log.completed
      log.count = log.completed ? @habit.target_count : 0
    end
    log.save!

    respond_to do |format|
      format.turbo_stream { render turbo_stream: toggle_today_streams }
      format.html         { redirect_back fallback_location: habits_path }
    end
  end

  private

  def set_habit
    @habit = current_user.habits.find(params[:id])
  end

  def habit_params
    params.require(:habit).permit(:name, :description, :frequency, :target_count, :color, :icon, :archived_at)
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
