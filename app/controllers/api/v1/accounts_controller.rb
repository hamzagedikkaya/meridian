module Api
  module V1
    class AccountsController < BaseController
      def index
        accounts = current_user.accounts.active.order(:name)
        render json: { accounts: accounts.map { |account| account_json(account) } }
      end

      private

      def account_json(account)
        {
          id: account.id,
          name: account.name,
          account_type: account.account_type,
          currency: account.currency,
          color: account.color,
          initial_balance_cents: account.initial_balance_cents,
          balance_cents: account.balance_cents,
          archived: account.archived?
        }
      end
    end
  end
end
