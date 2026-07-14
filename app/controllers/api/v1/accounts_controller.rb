module Api
  module V1
    class AccountsController < BaseController
      def index
        accounts = current_user.accounts.active.order(:name).to_a
        balances = balances_for(accounts)
        render json: { accounts: accounts.map { |account| account_json(account, balances[account.id]) } }
      end

      private

      # Mirrors Account#balance_cents for every account in a fixed number of
      # queries instead of four aggregates per account.
      def balances_for(accounts)
        ids = accounts.map(&:id)
        scoped = Transaction.where(account_id: ids)
        incomes       = scoped.where(kind: "income").group(:account_id).sum(:amount_cents)
        expenses      = scoped.where(kind: "expense").group(:account_id).sum(:amount_cents)
        transfers_out = scoped.where(kind: "transfer").group(:account_id).sum(:amount_cents)
        transfers_in  = Transaction.where(related_account_id: ids, kind: "transfer")
                                   .group(:related_account_id).sum(:amount_cents)

        accounts.each_with_object({}) do |account, memo|
          memo[account.id] = account.initial_balance_cents +
            incomes.fetch(account.id, 0) - expenses.fetch(account.id, 0) -
            transfers_out.fetch(account.id, 0) + transfers_in.fetch(account.id, 0)
        end
      end

      def account_json(account, balance_cents)
        {
          id: account.id,
          name: account.name,
          account_type: account.account_type,
          currency: account.currency,
          subunit_to_unit: Money::Currency.find(account.currency)&.subunit_to_unit || 100,
          color: account.color,
          initial_balance_cents: account.initial_balance_cents,
          balance_cents: balance_cents,
          archived: account.archived?
        }
      end
    end
  end
end
