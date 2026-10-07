module Finance
  class BaseController < ApplicationController
    private

    def user_accounts
      current_user.accounts.active.order(:name)
    end

    def user_categories(kind = nil)
      scope = current_user.finance_categories.ordered
      kind ? scope.where(kind: kind) : scope
    end

    # The chosen account's currency (the default one when none is chosen).
    # Its minor units per major unit (CurrencyUnit: 100 for TRY/USD/EUR, 1
    # for GAU, gram gold) convert the form's amount instead of a hardcoded
    # `amount * 100`, which mis-stored "5" as 500 grams of gold.
    def currency_for(account_id)
      account = current_user.accounts.find_by(id: account_id) if account_id.present?
      account&.currency || Money.default_currency.iso_code
    end

    # The form's amount (major units, "2.5") in the chosen account's minor
    # units.
    def minor_units_from_form(amount, account_id)
      minor_units_in(amount, currency_for(account_id))
    end

    # +amount+ (major units) in +currency+'s minor units. A fraction of the
    # smallest unit (1.5 grams of GAU, 0.005 TRY) is refused, as quick
    # capture refuses it, instead of being rounded into another amount: the
    # currency is noted and #amount_precise? fails the save, naming it (a
    # linked counter-transaction can be in another currency than the record
    # the error is shown on). Unreadable text reads as 0, which the model
    # refuses; so do "Infinity" and "NaN", which BigDecimal reads but which
    # have no whole number of minor units (rounding them raised a 500).
    def minor_units_in(amount, currency)
      value = BigDecimal(amount.to_s.strip, exception: false)
      value = BigDecimal(0) unless value&.finite?
      cents = value * CurrencyUnit.subunit_to_unit(currency)
      (@too_precise_currencies ||= []) << currency if cents.frac.nonzero?
      cents.round.to_i
    end

    # False, with the record's validation errors plus one precision error
    # per currency whose amount was too precise.
    def amount_precise?(record)
      return true if @too_precise_currencies.blank?

      record.validate
      @too_precise_currencies.uniq.each do |currency|
        record.errors.add(:base, t("quick_capture.invalid_amount.too_precise", currency: currency))
      end
      false
    end
  end
end
