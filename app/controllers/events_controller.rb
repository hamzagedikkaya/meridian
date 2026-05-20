class EventsController < ApplicationController
  before_action :set_event, only: [ :show, :edit, :update, :destroy ]

  def show
  end

  def new
    @event = current_user.events.new(
      start_at: (params[:date] ? Date.parse(params[:date]).beginning_of_day + 9.hours : Time.current.beginning_of_hour + 1.hour),
      event_type: "personal"
    )
  end

  def create
    @event = current_user.events.new(event_params)
    if @event.save
      redirect_to calendar_path, notice: "Event created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @event.update(event_params)
      redirect_to calendar_path, notice: "Event updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @event.destroy
    redirect_to calendar_path, notice: "Event deleted."
  end

  private

  def set_event
    @event = current_user.events.find(params[:id])
  end

  def event_params
    params.require(:event).permit(:title, :description, :start_at, :end_at, :all_day, :color, :location, :event_type, :recurring, :recurrence_rule)
  end
end
