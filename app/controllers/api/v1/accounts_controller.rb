module Api
  module V1
    class AccountsController < BaseController
      before_action :set_account, only: [ :show, :update, :destroy, :archive, :unarchive ]

      # Active accounts by name; include_archived=true appends the archived
      # ones, also by name. (The web's order(archived_at: :asc) would list
      # archived accounts first: PostgreSQL sorts NULLs last.)
      def index
        accounts = current_user.accounts.active.order(:name, :id).to_a
        accounts += current_user.accounts.archived.order(:name, :id).to_a if boolean_param(:include_archived)
        balances = balances_for(accounts)
        render json: { accounts: accounts.map { |account| account_json(account, balances) } }
      end

      # Archived accounts open too, like the web's show page.
      def show
        render json: { account: account_json(@account).merge(activity_json(@account)) }
      end

      # The web form's defaults: the user's currency, then the column
      # defaults (cash, opening balance 0, #B8860B).
      def create
        account = current_user.accounts.new(currency: current_user.currency)
        account.assign_attributes(account_attributes)

        if save_checked(account) { check_account(account) }
          render json: { account: account_json(account) }, status: :created
        else
          render_errors(account)
        end
      end

      # Every stored amount (transactions, subscriptions) is in the account
      # currency's minor units, so a new currency would silently re-read
      # them (100.00 TRY would become 10,000 grams of GAU). The currency can
      # only change while nothing is recorded on the account.
      def update
        @account.assign_attributes(account_attributes)
        if currency_switch?(@account) && in_use?(activity_counts(@account))
          return render_unprocessable(:currency_locked, field: :currency, message: I18n.t("api.errors.currency_locked"))
        end

        if save_checked(@account) { check_account(@account) }
          render json: { account: account_json(@account) }
        else
          render_errors(@account)
        end
      end

      # Only an account no transaction touches can be deleted. On the web a
      # delete also deletes the account's transactions (and their linked
      # counterparts on other accounts), and transfers into it from other
      # accounts lose their destination while still debiting the source
      # (Account#outgoing_transfers is dependent: :nullify). The client offers
      # archive instead. As on the web, its subscriptions go with it; goals
      # that tracked it are unlinked rather than left pointing at nothing.
      def destroy
        counts = activity_counts(@account)
        return render_has_transactions(counts) if transactions?(counts)

        Account.transaction do
          @account.subscriptions.destroy_all
          @account.tracking_goals.update_all(related_type: nil, related_id: nil, updated_at: Time.current)
          # delete, not destroy: a transaction recorded since the check then
          # trips the foreign key instead of being removed by the
          # dependent: :destroy cascade.
          @account.delete
        end
        head :no_content
      rescue ActiveRecord::InvalidForeignKey
        render_has_transactions(activity_counts(@account))
      end

      # Hides the account from the default list and the web's pickers; its
      # transactions keep counting everywhere. Idempotent.
      def archive
        @account.update!(archived_at: Time.current) unless @account.archived?
        render json: { account: account_json(@account) }
      end

      def unarchive
        @account.update!(archived_at: nil) if @account.archived?
        render json: { account: account_json(@account) }
      end

      private

      def set_account
        @account = current_user.accounts.find(params[:id])
      end

      # archived_at changes only through archive/unarchive. The opening
      # balance is in minor units, as the web form takes it
      # (finance/accounts/_form.html.erb), never a decimal.
      def account_attributes
        attrs = params.permit(:name, :account_type, :currency, :color).to_h
        attrs[:currency] = attrs[:currency].strip.upcase if attrs[:currency].is_a?(String)
        attrs[:initial_balance_cents] = integer_param(:initial_balance_cents) if params.key?(:initial_balance_cents)
        attrs
      end

      # The web prints balances with Money.new(cents, currency), which raises
      # for a code Money does not know; the model only checks the length.
      def check_account(account)
        check_color(account)
        return unless account.will_save_change_to_currency? && account.currency.present?

        account.errors.add(:currency, :inclusion, value: account.currency) unless Money::Currency.find(account.currency)
      end

      # Case is ignored, so normalizing a lowercase code stored through the
      # web's free-text field is not a switch.
      def currency_switch?(account)
        account.will_save_change_to_currency? &&
          account.currency.to_s.casecmp(account.currency_in_database.to_s).nonzero?
      end

      def activity_counts(account)
        {
          transactions_count: account.transactions.count,
          # Rows on other accounts that point here: transfers into this one.
          incoming_transfers_count: account.outgoing_transfers.count,
          subscriptions_count: account.subscriptions.count
        }
      end

      def transactions?(counts)
        counts[:transactions_count].positive? || counts[:incoming_transfers_count].positive?
      end

      def in_use?(counts)
        transactions?(counts) || counts[:subscriptions_count].positive?
      end

      def activity_json(account)
        counts = activity_counts(account)
        counts.merge(
          linked_goals_count: account.tracking_goals.count,
          deletable: !transactions?(counts),
          currency_editable: !in_use?(counts)
        )
      end

      def render_has_transactions(counts)
        render_unprocessable(:has_transactions,
          message: I18n.t("api.errors.has_transactions"),
          **counts.slice(:transactions_count, :incoming_transfers_count))
      end

      def account_json(account, balances = balances_for([ account ]))
        Serialize.account(account, balance_cents: balances.fetch(account.id))
      end

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
    end
  end
end
