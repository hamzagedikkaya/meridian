class QuickCapturesController < ApplicationController
  # POST /quick_captures
  # body: { text: "any string" }
  def create
    text = params[:text].to_s.strip
    redirect_to root_path, alert: t("quick_capture.empty_alert") and return if text.blank?

    case text
    when /^[+\-]?\d+(\.\d+)?/
      acc = current_user.accounts.active.first
      if acc.nil?
        redirect_to new_finance_account_path, alert: t("finance.accounts.create_first") and return
      end
      kind = text.start_with?("+") ? "income" : "expense"
      amount = (text.delete("^0-9.\-").to_f.abs * 100).round
      description = text.sub(/^[+\-]?[\d.]+\s*/, "")
      ::Transaction.create!(user: current_user, account: acc, amount_cents: amount, kind: kind, description: description.presence || t("quick_capture.button"), date: Date.current)
      redirect_to finance_transactions_path, notice: t("quick_capture.captured_transaction")

    when /^habit:\s*(.+)/i
      name = $1.strip
      habit = current_user.habits.active.find { |h| h.name.downcase == name.downcase }
      if habit
        log = habit.log_for(Date.current)
        log.update!(completed: true, count: 1)
        redirect_to habits_path, notice: t("quick_capture.logged_habit", name: habit.name)
      else
        redirect_to new_habit_path(habit: { name: name }), alert: t("quick_capture.habit_not_found", name: name)
      end

    when /(?:yarın|tomorrow|salı|monday|tuesday|wednesday|thursday|friday|saturday|sunday)/i
      redirect_to new_event_path(event: { title: text }), notice: t("quick_capture.looks_event")

    else
      todo = current_user.todos.create!(title: text, priority: "medium", status: "pending")
      redirect_to todos_path, notice: t("quick_capture.captured_todo", title: todo.title)
    end
  end
end
