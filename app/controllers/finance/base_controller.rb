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

    # How many minor units make one major unit for the chosen account's
    # currency — 100 for TRY/USD/EUR, 1 for GAU (gram gold), etc. We use this
    # to convert the form's :amount into :amount_cents instead of hardcoding
    # `amount * 100`, which mis-stored "5" as 500 grams of gold.
    def subunit_multiplier_for(account_id)
      return Money.default_currency.subunit_to_unit if account_id.blank?
      account = current_user.accounts.find_by(id: account_id)
      Money::Currency.find(account&.currency || Money.default_currency.iso_code)&.subunit_to_unit ||
        Money.default_currency.subunit_to_unit
    end
  end
end
