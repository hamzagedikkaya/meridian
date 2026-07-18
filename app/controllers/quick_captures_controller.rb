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
    when :transaction
      redirect_to finance_transactions_path, notice: t("quick_capture.captured_transaction")
    when :habit_log
      redirect_to habits_path, notice: t("quick_capture.logged_habit", name: result.name)
    when :habit_not_found
      redirect_to new_habit_path(habit: { name: result.name }), alert: t("quick_capture.habit_not_found", name: result.name)
    when :event_suggestion
      redirect_to new_event_path(event: { title: result.text }), notice: t("quick_capture.looks_event")
    when :todo
      redirect_to todos_path, notice: t("quick_capture.captured_todo", title: result.record.title)
    end
  end
end
