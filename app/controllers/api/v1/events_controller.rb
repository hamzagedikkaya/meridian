module Api
  module V1
    class EventsController < BaseController
      DEFAULT_SPAN_DAYS = 30

      def index
        from = parse_date(params[:from]) || Date.current
        to = parse_date(params[:to]) || from + DEFAULT_SPAN_DAYS.days

        scope = current_user.events.order(:start_at)
        events = scope.where(start_at: from.beginning_of_day..to.end_of_day)
                      .or(scope.recurring.where(start_at: ...from.beginning_of_day))

        payload = events.filter_map do |event|
          occurrences = event.occurrences_between(from, to).select { |date| date.between?(from, to) }
          next if occurrences.empty?

          Serialize.event(event, occurrences: occurrences)
        end

        render json: { events: payload }
      end

      private

      def parse_date(value)
        Date.iso8601(value.to_s)
      rescue ArgumentError
        nil
      end
    end
  end
end
