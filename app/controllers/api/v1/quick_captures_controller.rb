module Api
  module V1
    class QuickCapturesController < BaseController
      rescue_from ActiveRecord::RecordInvalid do |exception|
        render_errors(exception.record)
      end

      def create
        result = QuickCapture.call(current_user, params[:text])

        case result.type
        when :transaction
          render_capture("transaction", result.record.id, result.record.description)
        when :habit_log
          render_capture("habit_log", result.record.id, result.name)
        when :todo
          render_capture("todo", result.record.id, result.record.title)
        when :event_suggestion
          render json: { captured_type: "event_suggestion", record_id: nil, summary: result.text }
        when :empty
          render_capture_error(I18n.t("quick_capture.empty_alert"))
        when :no_account
          render_capture_error(I18n.t("finance.accounts.create_first"))
        when :habit_not_found
          render_capture_error(I18n.t("quick_capture.habit_not_found", name: result.name))
        end
      end

      private

      def render_capture(type, record_id, summary)
        render json: { captured_type: type, record_id: record_id, summary: summary }, status: :created
      end

      def render_capture_error(message)
        render json: { errors: { text: [ message ] } }, status: :unprocessable_entity
      end
    end
  end
end
