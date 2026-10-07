class EventsController < ApplicationController
  before_action :set_event, only: [ :show, :edit, :update, :destroy, :move, :reschedule ]
  before_action :refuse_series_drag, only: [ :move, :reschedule ]

  def show
  end

  def new
    @event = current_user.events.new(
      title: prefill_title,
      start_at: prefill_start_at,
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

  # A series is one row: its occurrences are expanded from start_at and the
  # rule. A dragged tile is one occurrence, so writing its drop day into
  # start_at would re-anchor the whole series there and silently drop every
  # occurrence before it. Moving one occurrence alone needs exceptions the
  # schema does not have, and shifting the whole series is not what a drag
  # shows, so the week and month views do not make a series draggable and
  # these drag endpoints refuse one (JSON for the Stimulus calls, a flash
  # otherwise). The series' form still changes its time.
  def refuse_series_drag
    return unless @event.repeats?

    message = t("events.series_not_draggable")
    respond_to do |format|
      format.json { render json: { ok: false, error: message }, status: :unprocessable_entity }
      format.any { redirect_to calendar_path, alert: message }
    end
  end

  # The calendar's "+" links here with ?date=YYYY-MM-DD; quick capture adds
  # &time=HH:MM and event[title] for text that looked like an event.
  def prefill_start_at
    day = Date.parse(params[:date].to_s).beginning_of_day if params[:date].present?
    return Time.current.beginning_of_hour + 1.hour unless day

    hour, minute = params[:time].to_s.match(/\A([01]\d|2[0-3]):([0-5]\d)\z/)&.captures&.map(&:to_i)
    hour ? day.change(hour: hour, min: minute) : day + 9.hours
  rescue Date::Error
    Time.current.beginning_of_hour + 1.hour
  end

  def prefill_title
    event = params[:event]
    title = event[:title] if event.is_a?(ActionController::Parameters)
    title if title.is_a?(String)
  end

  def event_params
    params.require(:event).permit(:title, :description, :start_at, :end_at, :all_day, :color, :location, :event_type, :recurring, :recurrence_rule)
  end
end
