class GoalsController < ApplicationController
  before_action :set_goal, only: [ :show, :edit, :update, :destroy, :recalculate, :update_progress ]

  def index
    @active_goals    = current_user.goals.active.ordered
    @achieved_goals  = current_user.goals.where(status: "achieved").ordered
    @abandoned_goals = current_user.goals.where(status: "abandoned").ordered
    @active_goals.each(&:recalculate_progress!)
  end

  def show
    @goal.recalculate_progress!
    @linkable_accounts = current_user.accounts.active.order(:name) if @goal.target_type == "financial"
    @linkable_habits   = current_user.habits.active.order(:name)   if @goal.target_type == "habit"
  end

  def new
    @goal = current_user.goals.new(target_type: "custom", status: "active", unit: current_user.currency)
    load_linkable
  end

  def create
    @goal = current_user.goals.new(goal_params)
    apply_related_param(@goal)
    if @goal.save
      redirect_to goal_path(@goal), notice: t("flash.saved")
    else
      load_linkable
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    load_linkable
  end

  def update
    apply_related_param(@goal)
    if @goal.update(goal_params)
      redirect_to goal_path(@goal), notice: t("flash.updated")
    else
      load_linkable
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @goal.destroy
    redirect_to goals_path, notice: t("flash.deleted")
  end

  def recalculate
    @goal.recalculate_progress!
    redirect_to goal_path(@goal)
  end

  # PATCH /goals/:id/update_progress
  # Params: { current_value: "5" } OR { delta: "1" } OR { delta: "-1" }
  # Used by the per-goal logging widget on the show page.
  def update_progress
    new_value = if params[:delta].present?
                  (@goal.current_value.to_f + params[:delta].to_f)
    elsif params[:current_value].present?
                  params[:current_value].to_f
    else
                  @goal.current_value
    end

    new_value = [ new_value, 0 ].max
    status = new_value >= @goal.target_value.to_f ? "achieved" : "active"
    @goal.update!(current_value: new_value, status: @goal.status == "abandoned" ? "abandoned" : status)

    redirect_to goal_path(@goal), notice: t("flash.updated")
  end

  private

  def set_goal
    @goal = current_user.goals.find(params[:id])
  end

  def load_linkable
    @linkable_accounts = current_user.accounts.active.order(:name)
    @linkable_habits   = current_user.habits.active.order(:name)
  end

  # Accept a composite param like "Account-12" or "Habit-7" from a single
  # combined select, and resolve it to the polymorphic related association.
  def apply_related_param(goal)
    raw = params.dig(:goal, :related)
    return if raw.blank?
    if raw == "none"
      goal.related = nil
      return
    end
    type, id = raw.to_s.split("-", 2)
    return unless %w[Account Habit].include?(type) && id.present?

    record = type.constantize.where(user_id: current_user.id).find_by(id: id)
    goal.related = record if record
  end

  def goal_params
    params.require(:goal).permit(:name, :description, :target_type, :target_value, :current_value, :unit, :deadline, :color, :status)
  end
end
