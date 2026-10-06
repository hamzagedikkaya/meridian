module Api
  module V1
    class EventsController < BaseController
      DEFAULT_SPAN_DAYS = 30
      MAX_SPAN_DAYS = 366

      before_action :set_event, only: [ :show, :update, :destroy ]

      def index
        from = parse_date(params[:from]) || Date.current
        to = parse_date(params[:to]) || from + DEFAULT_SPAN_DAYS.days
        # A recurring event materializes one object per occurrence, so an
        # uncapped `to` turns a single daily event into millions of allocations.
        to = [ to, from + MAX_SPAN_DAYS.days ].min
        to = from if to < from

        payload = Event.occurrences_by_event(current_user.events.order(:start_at), from, to).map do |event, occurrences|
          Serialize.event(event, occurrences: occurrences)
        end

        render json: { events: payload }
      end

      def show
        render json: { event: Serialize.event(@event, full: true) }
      end

      # The web's create (EventsController#create) with flat params. Unset
      # fields take the column defaults the web form starts from: personal,
      # #B8860B, not all-day, not recurring.
      def create
        event = current_user.events.new
        event.assign_attributes(event_attributes)
        save_event(event, :created)
      end

      # Only the keys sent change. A recurring event is a single row expanded
      # at read time, so an edit applies to the whole series, and a new
      # start_at moves the series' anchor (and with it every occurrence).
      # There is no per-occurrence override.
      def update
        @event.assign_attributes(event_attributes)
        save_event(@event, :ok)
      end

      # As on the web; for a recurring event that is the whole series.
      def destroy
        @event.destroy!
        head :no_content
      end

      private

      def set_event
        @event = current_user.events.find(params[:id])
      end

      # A filter date (contract 1.3): exactly YYYY-MM-DD, else nil, which
      # leaves the default window. Date.iso8601 alone would also read
      # "2026-10" or "2026-W40-4" as some day of that month or week.
      def parse_date(value)
        Date.iso8601(value) if value.is_a?(String) && value.match?(ISO_DATE)
      rescue ArgumentError
        nil
      end

      def save_event(event, status)
        span_whole_days(event)
        if save_checked(event) { check_color(event) }
          render json: { event: Serialize.event(event, full: true) }, status: status
        else
          render_errors(event)
        end
      end

      # The web form's fields (EventsController#event_params). `recurring`
      # is not taken: it follows recurrence_rule (null or "" stops the
      # series), which the model checks and normalizes (RecurrenceRule).
      def event_attributes
        attrs = params.permit(:title, :description, :location, :color, :event_type).to_h
        attrs[:start_at] = datetime_param(:start_at) if params.key?(:start_at)
        attrs[:end_at] = datetime_param(:end_at) if params.key?(:end_at)
        attrs[:all_day] = required_boolean_param(:all_day) if params.key?(:all_day)
        if params.key?(:recurrence_rule)
          rule = string_param(:recurrence_rule)
          attrs[:recurrence_rule] = rule.presence
          attrs[:recurring] = rule.present?
        end
        attrs
      end

      # An all-day event covers whole days in the user's zone: it starts at
      # 00:00 on its first day and, when it has an end, ends at 23:59:59 on
      # its last day. Applied when the event is or becomes all-day or its
      # times change, so a title edit leaves an older row's times alone.
      def span_whole_days(event)
        return unless event.all_day? && event.start_at
        return unless event.will_save_change_to_all_day? || event.will_save_change_to_start_at? ||
                      event.will_save_change_to_end_at?

        event.start_at = event.start_at.beginning_of_day
        event.end_at = event.end_at.change(hour: 23, min: 59, sec: 59) if event.end_at
      end
    end
  end
end
