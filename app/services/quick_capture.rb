# Parses a free-text capture ("-250 kahve", "habit: koşu", "süt al") into a
# record, shared by the web and API quick-capture controllers.
class QuickCapture
  Result = Struct.new(:type, :record, :name, :text, keyword_init: true)

  def self.call(user, text)
    new(user, text).call
  end

  def initialize(user, text)
    @user = user
    @text = text.to_s.strip
  end

  def call
    return result(:empty) if @text.blank?

    case @text
    when /^[+\-]?\d+(\.\d+)?/
      capture_transaction
    when /^habit:\s*(.+)/i
      capture_habit($1.strip)
    when /(?:yarın|tomorrow|salı|monday|tuesday|wednesday|thursday|friday|saturday|sunday)/i
      result(:event_suggestion)
    else
      result(:todo, record: @user.todos.create!(title: @text, priority: "medium", status: "pending"))
    end
  end

  private

  def capture_transaction
    account = @user.accounts.active.first
    return result(:no_account) if account.nil?

    kind = @text.start_with?("+") ? "income" : "expense"
    subunit = Money::Currency.find(account.currency)&.subunit_to_unit || 100
    amount = (@text.delete("^0-9.\-").to_f.abs * subunit).round
    description = @text.sub(/^[+\-]?[\d.]+\s*/, "")
    record = ::Transaction.create!(
      user: @user, account: account, amount_cents: amount, kind: kind,
      description: description.presence || I18n.t("quick_capture.button"), date: Date.current
    )
    result(:transaction, record: record)
  end

  def capture_habit(name)
    habit = @user.habits.active.find { |h| h.name.downcase == name.downcase }
    return result(:habit_not_found, name: name) if habit.nil?

    log = habit.log_for(Date.current)
    log.update!(completed: true, count: 1)
    result(:habit_log, record: log, name: habit.name)
  end

  def result(type, record: nil, name: nil)
    Result.new(type: type, record: record, name: name, text: @text)
  end
end
