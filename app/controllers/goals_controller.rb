class GoalsController < ApplicationController
  before_action :set_goal, only: [ :show, :edit, :update, :destroy, :recalculate ]

  def index
    @active_goals    = current_user.goals.active.ordered
    @achieved_goals  = current_user.goals.where(status: "achieved").ordered
    @abandoned_goals = current_user.goals.where(status: "abandoned").ordered
    @active_goals.each(&:recalculate_progress!)
  end

  def show
    @goal.recalculate_progress!
  end

  def new
    @goal = current_user.goals.new(target_type: "custom", status: "active", unit: current_user.currency)
  end

  def create
    @goal = current_user.goals.new(goal_params)
    if @goal.save
      redirect_to goals_path, notice: "Goal created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @goal.update(goal_params)
      redirect_to goals_path, notice: "Goal updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @goal.destroy
    redirect_to goals_path, notice: "Goal deleted."
  end

  def recalculate
    @goal.recalculate_progress!
    redirect_to goal_path(@goal)
  end

  private

  def set_goal
    @goal = current_user.goals.find(params[:id])
  end

  def goal_params
    params.require(:goal).permit(:name, :description, :target_type, :target_value, :current_value, :unit, :deadline, :color, :status)
  end
end
