class QuickCapturesController < ApplicationController
  # POST /quick_captures
  # body: { text: "any string" }
  def create
    result = QuickCapture.call(current_user, params[:text])

    case result.type
    when :empty
      redirect_to root_path, alert: t("quick_capture.empty_alert")
    when :no_account
      redirect_to new_finance_account_path, alert: t("finance.accounts.create_first")
    when :invalid_amount
      redirect_back_or_to root_path, alert: result.amount_error_message
    when :invalid
      redirect_back_or_to root_path, alert: result.record.errors.full_messages.to_sentence
    when :transaction
      redirect_to finance_transactions_path, notice: t("quick_capture.captured_transaction")
    when :habit_log
      redirect_to habits_path, notice: t("quick_capture.logged_habit", name: result.name)
    when :unknown_habit
      redirect_to new_habit_path(habit: { name: result.name }), alert: t("quick_capture.habit_not_found", name: result.name)
    when :event_suggestion
      hint = result.suggestion
      prefill = { date: hint.date.iso8601, time: hint.time, event: { title: hint.title } }.compact
      redirect_to new_event_path(prefill), notice: t("quick_capture.looks_event")
    when :todo
      redirect_to todos_path, notice: t("quick_capture.captured_todo", title: result.record.title)
    end
  end
end
