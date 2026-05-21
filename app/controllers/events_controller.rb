class EventsController < ApplicationController
  before_action :set_event, only: [ :show, :edit, :update, :destroy, :move, :reschedule ]

  def show
  end

  def new
    @event = current_user.events.new(
      start_at: (params[:date] ? Date.parse(params[:date]).beginning_of_day + 9.hours : Time.current.beginning_of_hour + 1.hour),
      event_type: "personal",
      color: "#B8860B"
    )
  end

  def create
    @event = current_user.events.new(event_params)
    if @event.save
      redirect_to calendar_path, notice: t("flash.saved")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @event.update(event_params)
      redirect_to calendar_path, notice: t("flash.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @event.destroy
    redirect_to calendar_path, notice: t("flash.deleted")
  end

  # PATCH /events/:id/move
  # Body: { date: "2026-05-22" }
  # Moves the event to a new date while preserving its time of day. Used by
  # the monthly calendar drag-and-drop.
  def move
    new_date = Date.parse(params.require(:date))
    duration = @event.end_at ? (@event.end_at - @event.start_at) : nil
    new_start = new_date.beginning_of_day + (@event.start_at - @event.start_at.beginning_of_day)
    new_end   = duration ? new_start + duration : nil

    if @event.update(start_at: new_start, end_at: new_end)
      render json: { ok: true, start_at: @event.start_at.iso8601, end_at: @event.end_at&.iso8601 }
    else
      render json: { ok: false, errors: @event.errors.full_messages }, status: :unprocessable_entity
    end
  rescue ArgumentError
    render json: { ok: false, error: "Invalid date" }, status: :bad_request
  end

  # PATCH /events/:id/reschedule
  # Body: { start_at: "2026-05-22T14:00", end_at: "2026-05-22T15:00" }
  # Used by the weekly view vertical drag (time-of-day adjustment).
  def reschedule
    new_start = Time.zone.parse(params.require(:start_at))
    new_end   = params[:end_at].present? ? Time.zone.parse(params[:end_at]) : @event.end_at

    if @event.update(start_at: new_start, end_at: new_end)
      render json: { ok: true }
    else
      render json: { ok: false, errors: @event.errors.full_messages }, status: :unprocessable_entity
    end
  rescue ArgumentError
    render json: { ok: false, error: "Invalid time" }, status: :bad_request
  end

  private

  def set_event
    @event = current_user.events.find(params[:id])
  end

  def event_params
    params.require(:event).permit(:title, :description, :start_at, :end_at, :all_day, :color, :location, :event_type, :recurring, :recurrence_rule)
  end
end
