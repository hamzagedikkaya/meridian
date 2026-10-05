module Api
  module V1
    class CurrenciesController < BaseController
      # The currencies the app offers for a new account (GAU is the gram-gold
      # unit registered in config/initializers/money.rb).
      OFFERED = %w[TRY USD EUR GBP GAU].freeze

      # The offered currencies, then any other one the user already uses
      # (their own currency or an account's), so an existing account's
      # currency always has an entry. Codes Money does not know are left out:
      # an account cannot be given one (POST /accounts refuses it). Also the
      # currency picker of GET /me/options.
      def self.offered_to(user)
        in_use = [ user.currency, *user.accounts.distinct.pluck(:currency) ].map { |code| code.to_s.upcase }
        (OFFERED + in_use.sort).uniq.filter_map { |code| Money::Currency.find(code) }
      end

      def index
        render json: {
          currencies: self.class.offered_to(current_user).map { |currency| Serialize.currency(currency) },
          default_currency: current_user.currency.to_s.upcase
        }
      end
    end
  end
end
