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
    # Series anchored before the grid too (Event.occurrences_by_event), as
    # GET /api/v1/events lists them.
    Event.occurrences_by_event(current_user.events.order(:start_at), @grid_start, @grid_end).each do |e, dates|
      dates.each { |d| @events_by_date[d] << e }
    end

    # Cross-module overlays. beginning_of_day: a bare Date would be compared
    # with due_at as UTC midnight, not the user's.
    current_user.todos.where.not(due_at: nil).where(due_at: @grid_start.beginning_of_day..@grid_end.end_of_day).find_each do |t|
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

    # Each occurrence of a series on its own day. All-day events, and timed
    # ones outside the hour grid, go in the strip above it (@all_day_by_day)
    # instead of being left out.
    @events_by_day = Hash.new { |h, k| h[k] = [] }
    @all_day_by_day = Hash.new { |h, k| h[k] = [] }
    Event.occurrences_by_event(current_user.events.order(:start_at), @week_start, @week_end).each do |e, dates|
      start_minutes = e.start_at.hour * 60 + e.start_at.min - @hours.first * 60
      in_grid = !e.all_day && start_minutes >= 0 && start_minutes < @hours.size * 60
      dates.each { |d| (in_grid ? @events_by_day : @all_day_by_day)[d] << e }
    end
  rescue ArgumentError
    redirect_to calendar_week_path
  end

  # Upcoming one-off events, and every series (one VEVENT with its RRULE, so
  # a series anchored in the past still shows its future occurrences).
  def feed
    scope = current_user.events
    events = scope.where(start_at: Time.current..).or(scope.recurring.where.not(recurrence_rule: nil)).order(:start_at)
    entries = events.filter_map do |e|
      rule = RecurrenceRule.new(e.recurrence_rule) if e.repeats?
      series = IcalRecurrence.new(e, rule) if rule&.valid?
      # A series that never occurs is listed nowhere else either.
      next if series && series.first_start.nil?

      [ e, series ] unless series.nil? && e.start_at < Time.current
    end
    zoned = entries.select { |e, series| series && !e.all_day }.map { |_, series| series.first_start }
    zone = IcalTimeZone.new(Time.zone, from: zoned.min - 1.day) if zoned.any?

    ical = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Meridian//EN\r\n"
    ical << zone.to_ical if zone
    entries.each do |e, series|
      ical << "BEGIN:VEVENT\r\n"
      ical << "UID:meridian-#{e.id}@local\r\n"
      ical << ical_times(e, (zone if series), start: series&.first_start || e.start_at)
      ical << ical_recurrence(e, series, zone) if series
      ical << "SUMMARY:#{ical_escape(e.title)}\r\n"
      ical << "DESCRIPTION:#{ical_escape(e.description)}\r\n" if e.description.present?
      ical << "LOCATION:#{ical_escape(e.location)}\r\n" if e.location.present?
      ical << "END:VEVENT\r\n"
    end
    ical << "END:VCALENDAR\r\n"
    send_data ical, type: "text/calendar", filename: "meridian.ics"
  end

  private

  # An all-day event is a DATE (RFC 5545 §3.6.1: DTEND is the day after its
  # last day). A timed one-off is a UTC instant. A timed series is the
  # user's wall clock with the feed's VTIMEZONE (+zone+): a client expands
  # an RRULE in DTSTART's zone, and from a UTC start it would put an
  # Istanbul Monday 01:00 series on Sundays (22:00 UTC), while the server
  # expands it in the user's zone. A series starts at +start+, its first
  # occurrence (IcalRecurrence), and keeps the event's length.
  def ical_times(event, zone = nil, start: event.start_at)
    if event.all_day
      first = start.to_date
      days = event.end_at ? [ (event.end_at.to_date - event.start_at.to_date).to_i, 0 ].max : 0
      "DTSTART;VALUE=DATE:#{ical_date(first)}\r\nDTEND;VALUE=DATE:#{ical_date(first + days + 1)}\r\n"
    else
      finish = start + (event.end_at ? event.end_at - event.start_at : 1.hour)
      if zone
        "DTSTART;TZID=#{zone.tzid}:#{ical_local(start)}\r\nDTEND;TZID=#{zone.tzid}:#{ical_local(finish)}\r\n"
      else
        "DTSTART:#{ical_utc(start)}\r\nDTEND:#{ical_utc(finish)}\r\n"
      end
    end
  end

  # The series' RRULE lines (IcalRecurrence#rules), or its occurrences as
  # RDATEs when no rule spells it. With a DATE start, UNTIL must be a DATE
  # too (RFC 5545 §3.3.10): the day of the stored instant in the user's zone.
  def ical_recurrence(event, series, zone)
    rules = series.rules.map do |text|
      if event.all_day
        text = text.gsub(/UNTIL=(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z/) do
          "UNTIL=#{ical_date(Time.utc(*Regexp.last_match.captures.map(&:to_i)).in_time_zone)}"
        end
      end
      "RRULE:#{text}\r\n"
    end
    dates = series.rdates.map do |time|
      event.all_day ? "RDATE;VALUE=DATE:#{ical_date(time.to_date)}\r\n" : "RDATE;TZID=#{zone.tzid}:#{ical_local(time)}\r\n"
    end
    (rules + dates).join
  end

  def ical_date(date)
    date.strftime("%Y%m%d")
  end

  def ical_local(time)
    time.in_time_zone(Time.zone).strftime("%Y%m%dT%H%M%S")
  end

  def ical_utc(time)
    time.utc.strftime("%Y%m%dT%H%M%SZ")
  end

  # RFC 5545 §3.3.11: backslash, semicolon and comma are escaped, and a literal
  # newline would otherwise end the property and let the next line inject one.
  def ical_escape(value)
    # Block form on purpose: gsub interprets backslash sequences in a string
    # replacement, which would silently undo the escaping.
    value.to_s.gsub(/[\\;,]|\r?\n/) do |match|
      case match
      when "\\" then "\\\\"
      when ";"  then "\\;"
      when ","  then "\\,"
      else           "\\n"
      end
    end
  end
end
