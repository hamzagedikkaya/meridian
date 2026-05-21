require "ostruct"

class CalendarController < ApplicationController
  def index
    year  = params[:year]&.to_i  || Date.current.year
    month = params[:month]&.to_i || Date.current.month
    @month_start = Date.new(year, month, 1)
    @month_end   = @month_start.end_of_month
    @prev_month  = @month_start - 1.month
    @next_month  = @month_start + 1.month

    # Calendar grid: 6 weeks aligned to start of week
    @grid_start = @month_start.beginning_of_week(:monday)
    @grid_end   = @grid_start + 41.days

    @events_by_date = Hash.new { |h, k| h[k] = [] }
    current_user.events.where(start_at: @grid_start.beginning_of_day..@grid_end.end_of_day).each do |e|
      e.occurrences_between(@grid_start, @grid_end).each do |d|
        @events_by_date[d] << e
      end
    end

    # Cross-module overlays
    current_user.todos.where.not(due_at: nil).where(due_at: @grid_start..@grid_end.end_of_day).find_each do |t|
      @events_by_date[t.due_at.to_date] << OpenStruct.new(
        title: "📌 #{t.title}", color: "#A09B8E", event_type: "todo", id: nil
      )
    end
    current_user.subscriptions.active.where(next_charge_on: @grid_start..@grid_end).find_each do |s|
      @events_by_date[s.next_charge_on] << OpenStruct.new(
        title: "💳 #{s.name}", color: "#B85450", event_type: "subscription", id: nil
      )
    end
  end

  # Weekly view — vertical hour grid with draggable events.
  def week
    anchor = params[:date].present? ? Date.parse(params[:date]) : Date.current
    @week_start = anchor.beginning_of_week(:monday)
    @week_end   = @week_start + 6.days
    @prev_week  = @week_start - 7.days
    @next_week  = @week_start + 7.days

    @hours = (6..22).to_a # 6 AM to 10 PM

    @events_by_day = Hash.new { |h, k| h[k] = [] }
    current_user.events.where(start_at: @week_start.beginning_of_day..@week_end.end_of_day)
                       .order(:start_at).each do |e|
      @events_by_day[e.start_at.to_date] << e
    end
  rescue ArgumentError
    redirect_to calendar_week_path
  end

  def feed
    events = current_user.events.upcoming
    ical = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Meridian//EN\r\n"
    events.each do |e|
      ical << "BEGIN:VEVENT\r\n"
      ical << "UID:meridian-#{e.id}@local\r\n"
      ical << "DTSTART:#{e.start_at.utc.strftime('%Y%m%dT%H%M%SZ')}\r\n"
      ical << "DTEND:#{(e.end_at || e.start_at + 1.hour).utc.strftime('%Y%m%dT%H%M%SZ')}\r\n"
      ical << "SUMMARY:#{e.title}\r\n"
      ical << "DESCRIPTION:#{e.description.to_s.gsub(/\r?\n/, '\\n')}\r\n" if e.description.present?
      ical << "LOCATION:#{e.location}\r\n" if e.location.present?
      ical << "END:VEVENT\r\n"
    end
    ical << "END:VCALENDAR\r\n"
    send_data ical, type: "text/calendar", filename: "meridian.ics"
  end
end
