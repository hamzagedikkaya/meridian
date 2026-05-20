module ApplicationHelper
  # Format Money or cent-integer in a consistent way across the app.
  def money_format(value, currency: nil)
    return "—" if value.blank?

    money = case value
    when Money   then value
    when Integer then Money.new(value, currency || Money.default_currency)
    when Numeric then Money.from_amount(value, currency || Money.default_currency)
    else nil
    end
    money&.format(symbol: true, no_cents_if_whole: false) || value.to_s
  end

  def signed_amount_class(kind)
    case kind.to_s
    when "income"   then "text-[var(--color-income)]"
    when "expense"  then "text-[var(--color-expense)]"
    when "transfer" then "text-[var(--color-info)]"
    else "text-[var(--color-fg-muted)]"
    end
  end

  def signed_amount_prefix(kind)
    case kind.to_s
    when "income"   then "+"
    when "expense"  then "−"
    when "transfer" then "→"
    else ""
    end
  end
end
