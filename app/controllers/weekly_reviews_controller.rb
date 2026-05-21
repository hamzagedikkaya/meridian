class WeeklyReviewsController < ApplicationController
  before_action :set_review, only: [ :show, :edit, :update ]

  def create
    @review = current_user.weekly_reviews.find_or_initialize_by(week_starting: params[:weekly_review][:week_starting])
    if @review.update(review_params.merge(completed_at: Time.current))
      redirect_to weekly_reviews_path, notice: t("flash.saved")
    else
      summarize_week
      render :edit, status: :unprocessable_entity
    end
  end

  def index
    @reviews = current_user.weekly_reviews.recent.limit(20)
    @this_week_review = current_user.weekly_reviews.find_by(week_starting: Date.current.beginning_of_week)
  end

  def new
    week_start = Date.current.beginning_of_week
    @review = current_user.weekly_reviews.find_or_initialize_by(week_starting: week_start)
    summarize_week
    render :edit
  end

  def show
    summarize_week
  end

  def edit
    summarize_week
  end

  def update
    if @review.update(review_params.merge(completed_at: Time.current))
      redirect_to weekly_reviews_path, notice: t("flash.saved")
    else
      summarize_week
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_review
    @review = current_user.weekly_reviews.find(params[:id])
  end

  def summarize_week
    start = @review.week_starting
    finish = start + 6.days
    @stats = {
      habits_completed:  current_user.habit_logs.where(completed: true, date: start..finish).count,
      todos_completed:   current_user.todos.where(status: "done", completed_at: start.beginning_of_day..finish.end_of_day).count,
      transactions_net:  current_user.transactions.between(start, finish).income.sum(:amount_cents) -
                         current_user.transactions.between(start, finish).expense.sum(:amount_cents),
      avg_mood:          current_user.journal_entries.where(date: start..finish).where.not(mood: nil).group(:mood).count,
      focus_minutes:     current_user.focus_sessions.where(started_at: start.beginning_of_day..finish.end_of_day).focus_only.sum(:duration_seconds) / 60
    }
  end

  def review_params
    params.require(:weekly_review).permit(:reflection_went_well, :reflection_learned, :reflection_next_week)
  end
end
