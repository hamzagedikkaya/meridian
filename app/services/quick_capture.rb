# Turns a free-text capture ("-250 kahve", "habit: koşu", "süt al") into a
# record, shared by the web and API quick-capture controllers. Parsing rules
# live in QuickCapture::Parser; this class looks up and writes records.
#
# Result types:
#   saved:     :transaction, :habit_log, :todo (record set)
#   not saved: :event_suggestion (suggestion set), :empty, :no_account,
#              :unknown_habit (name set), :invalid_amount (reason set),
#              :invalid (record carries validation errors)
class QuickCapture
  # transactions.amount_cents is a 4-byte integer.
  MAX_AMOUNT_CENTS = 2_147_483_647

  Result = Struct.new(:type, :record, :name, :text, :suggestion, :reason, :currency, keyword_init: true) do
    def amount_error_message
      I18n.t("quick_capture.invalid_amount.#{reason}", currency: currency)
    end
  end

  def self.call(user, text, as: nil, account: nil)
    new(user, text, as: as, account: account).call
  end

  # as: :todo saves the text as a todo without interpreting it, for when the
  # parser guessed wrong (an event suggestion the user wants as a task).
  # account: one of the user's accounts for a money capture; nil means the
  # oldest active one. Callers check that it is the user's.
  def initialize(user, text, as: nil, account: nil)
    @user = user
    @text = text.to_s.strip
    @as = as&.to_sym
    @account = account
  end

  def call
    return result(:empty) if @text.blank?
    return capture_todo if @as == :todo

    case (parsed = Parser.parse(@text, today: Date.current))
    when Parser::MoneyEntry then capture_transaction(parsed)
    when Parser::HabitEntry then capture_habit(parsed.name)
    when Parser::EventHint then result(:event_suggestion, suggestion: parsed)
    else capture_todo
    end
  end

  private

  def capture_transaction(parsed)
    return result(:invalid_amount, reason: :unreadable) if parsed.amount.nil?

    # The chosen account, else the oldest active one, as before; archiving
    # it moves captures on.
    account = @account || @user.accounts.active.order(:id).first
    return result(:no_account) if account.nil?

    cents = parsed.amount * CurrencyUnit.subunit_to_unit(account.currency)
    reason = amount_problem(cents)
    return result(:invalid_amount, reason: reason, currency: account.currency) if reason

    transaction = ::Transaction.create(
      user: @user, account: account, amount_cents: cents.to_i, kind: parsed.kind,
      description: parsed.description.presence || I18n.t("quick_capture.default_description"),
      date: Date.current
    )
    saved_or_invalid(:transaction, transaction)
  end

  # Fractions of the smallest unit (1,5 gram of GAU, 0,005 TRY) are refused
  # rather than rounded: silently storing 2 grams for 1,5 is worse than asking.
  def amount_problem(cents)
    if cents.zero? then :zero
    elsif cents.frac.nonzero? then :too_precise
    elsif cents > MAX_AMOUNT_CENTS then :too_large
    end
  end

  # Daily habits move one step towards the target per capture (a glass of
  # water for "8 glasses a day"); weekly and monthly habits count days, so the
  # capture marks today done. Never a flip: capturing twice cannot undo it.
  def capture_habit(name)
    return result(:empty) if name.blank?

    habit = find_habit(name)
    return result(:unknown_habit, name: name) if habit.nil?

    today = Date.current
    count = habit.daily? ? habit.habit_logs.find_by(date: today)&.count.to_i + 1 : habit.target_count
    result(:habit_log, record: habit.set_log_count!(today, count), name: habit.name)
  end

  # Exact name first (any case), then one that differs only in Turkish
  # letters or accents ("kosu" for "Koşu", "ingilizce" for "İngilizce").
  def find_habit(name)
    habits = @user.habits.active.to_a
    exact = habits.find { |habit| habit.name.casecmp?(name) }
    return exact if exact

    folded = fold(name)
    matches = habits.select { |habit| fold(habit.name) == folded }
    matches.first if matches.one?
  end

  def fold(text)
    text.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").downcase.tr("ı", "i").squish
  end

  def capture_todo
    saved_or_invalid(:todo, @user.todos.create(title: @text, priority: "medium", status: "pending"))
  end

  def saved_or_invalid(type, record)
    record.persisted? ? result(type, record: record) : result(:invalid, record: record)
  end

  def result(type, **attributes)
    Result.new(type: type, text: @text, **attributes)
  end
end
