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
    return value.to_s unless money

    opts = { symbol: true, no_cents_if_whole: false }
    opts[:format] = "%n %u" if money.currency.symbol_first == false
    money.format(opts)
  end

  # A stored minor-unit amount as a form's major-unit value in its currency:
  # 1250 TRY cents is "12.5", 250 grams of GAU (1 unit per gram) is "250.0".
  def amount_field_value(cents, currency)
    (BigDecimal(cents.to_i) / CurrencyUnit.subunit_to_unit(currency)).to_s("F")
  end

  # What an amount field shows: after a refused save, the text the user sent
  # in params[+form+][+field+] ("1.5" grams stays "1.5"; the record holds the
  # rounded 2, and showing that would let one more click save it, out of
  # step with the error); otherwise the block's value, the stored amount.
  def amount_form_value(record, form, field)
    sent = params[form][field] if record.errors.any? && params[form].is_a?(ActionController::Parameters)
    sent.is_a?(String) && sent.present? ? sent : yield
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
