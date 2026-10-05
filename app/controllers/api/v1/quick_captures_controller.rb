module Api
  module V1
    # POST /api/v1/quick_captures {text, as?, account_id?}
    #
    # Every 201 says what was saved (`captured_type`, `record_id`, `record`).
    # An event suggestion saves nothing: it answers 200 with saved: false and
    # the parsed title/date so the client can open a prefilled event form, or
    # resend with as=todo. Failures are 422 with a stable `code`.
    class QuickCapturesController < BaseController
      CAPTURE_AS = %w[todo].freeze

      def create
        result = QuickCapture.call(current_user, capture_text, as: capture_as, account: capture_account)

        case result.type
        when :transaction then render_transaction(result.record)
        when :habit_log then render_habit_log(result.record, result.name)
        when :todo then render_todo(result.record)
        when :event_suggestion then render_event_suggestion(result)
        when :invalid then render_errors(result.record)
        else render_capture_error(result)
        end
      end

      private

      # Only a string is text to capture; a list or an object is dropped, as
      # if it had not been sent (422 empty), instead of being saved as its
      # Ruby inspection ('["süt al"]').
      def capture_text
        params[:text] if params[:text].is_a?(String)
      end

      # Absent or null: the rules decide. "" is refused like any other value
      # than "todo" (choice_param alone reads it as not sent): the app only
      # ever sends "todo", so a blank one is a client bug, not a choice.
      def capture_as
        raise InvalidParameter, :as if params[:as] == ""

        choice_param(:as, CAPTURE_AS)
      end

      # The account a money capture goes to: one of the user's, archived ones
      # included as POST /transactions allows. Absent, null or "" leaves the
      # oldest active account. Checked whatever the text turns out to be, so
      # a bad id fails the same way for every capture.
      def capture_account
        owned_record_param(current_user.accounts, :account_id)
      end

      def render_transaction(transaction)
        render_saved("transaction", transaction.id,
          summary: transaction.description,
          message: I18n.t("quick_capture.captured_transaction"),
          record: Serialize.transaction(transaction))
      end

      def render_habit_log(log, habit_name)
        render_saved("habit_log", log.id,
          summary: habit_name,
          message: I18n.t("quick_capture.logged_habit", name: habit_name),
          record: { id: log.id, habit_id: log.habit_id, date: log.date, count: log.count, completed: log.completed })
      end

      def render_todo(todo)
        render_saved("todo", todo.id,
          summary: todo.title,
          message: I18n.t("quick_capture.captured_todo", title: todo.title),
          record: Serialize.todo(todo))
      end

      def render_saved(type, record_id, summary:, message:, record:)
        render json: {
          saved: true, captured_type: type, record_id: record_id,
          summary: summary, message: message, record: record
        }, status: :created
      end

      def render_event_suggestion(result)
        hint = result.suggestion
        render json: {
          saved: false,
          captured_type: "event_suggestion",
          record_id: nil,
          summary: result.text,
          message: I18n.t("quick_capture.looks_event"),
          suggestion: {
            title: hint.title,
            date: hint.date,
            time: hint.time,
            start_at: hint.time && Time.zone.parse("#{hint.date.iso8601} #{hint.time}"),
            all_day: hint.time.nil?,
            keyword: hint.keyword
          }
        }
      end

      def render_capture_error(result)
        case result.type
        when :empty
          render_unprocessable(:empty, field: :text, message: I18n.t("quick_capture.empty_alert"))
        when :no_account
          render_unprocessable(:no_account, field: :text, message: I18n.t("finance.accounts.create_first"))
        when :unknown_habit
          render_unprocessable(:unknown_habit, field: :text,
            message: I18n.t("quick_capture.habit_not_found", name: result.name), name: result.name)
        when :invalid_amount
          render_unprocessable(:invalid_amount, field: :text,
            message: result.amount_error_message, reason: result.reason.to_s)
        end
      end
    end
  end
end
