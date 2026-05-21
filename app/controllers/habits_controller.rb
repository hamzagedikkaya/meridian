class HabitsController < ApplicationController
  before_action :set_habit, only: [ :show, :edit, :update, :destroy, :toggle_today ]

  def index
    @habits = current_user.habits.active.includes(:habit_logs).order(:name)
  end

  def show
    @logs = @habit.habit_logs.where(date: (Date.current - 84.days)..Date.current).order(:date)
    @logs_by_date = @logs.index_by(&:date)
    @start_date = (Date.current - 83.days).beginning_of_week
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
    log.completed = !log.completed
    log.count = log.completed ? 1 : 0
    log.save!
    redirect_back fallback_location: habits_path
  end

  private

  def set_habit
    @habit = current_user.habits.find(params[:id])
  end

  def habit_params
    params.require(:habit).permit(:name, :description, :frequency, :target_count, :color, :icon, :archived_at)
  end
end
