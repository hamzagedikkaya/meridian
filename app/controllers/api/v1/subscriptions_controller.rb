module Api
  module V1
    class SubscriptionsController < BaseController
      PERIODS = { "weekly" => 1.week, "monthly" => 1.month, "yearly" => 1.year }.freeze

      before_action :set_subscription, only: [ :show, :update, :destroy, :charge ]

      # Like the web page: active subscriptions by next charge date, then the
      # inactive ones (here by name). Amounts are in each account's currency,
      # so the totals come per currency.
      def index
        scope = current_user.subscriptions.includes(:account, :finance_category)
        active = scope.active.order(:next_charge_on, :id).to_a
        render json: {
          active: active.map { |subscription| Serialize.subscription(subscription) },
          inactive: scope.inactive.order(:name, :id).map { |subscription| Serialize.subscription(subscription) },
          totals: totals(active)
        }
      end

      def show
        render json: { subscription: Serialize.subscription(@subscription) }
      end

      # The web form's defaults (Finance::SubscriptionsController#new):
      # active, monthly, starting today. Without next_charge_on, the first
      # charge is the first date on the start date's cycle after today; for
      # the defaults that is today + 1 month, the date the web form proposes.
      def create
        subscription = current_user.subscriptions.new(active: true, frequency: "monthly", start_date: Date.current)
        subscription.assign_attributes(subscription_attributes)
        subscription.next_charge_on = first_charge_on(subscription) unless params.key?(:next_charge_on)

        if save_checked(subscription) { check_subscription(subscription) }
          render json: { subscription: Serialize.subscription(subscription) }, status: :created
        else
          render_errors(subscription)
        end
      end

      # amount_cents is in the account currency's minor units, so moving the
      # subscription to an account in another currency needs the amount in
      # that currency too; otherwise it would be silently re-read.
      def update
        previous_currency = (@subscription.account&.currency).to_s
        @subscription.assign_attributes(subscription_attributes)
        if currency_switch?(@subscription, previous_currency) && !params.key?(:amount_cents)
          return render_unprocessable(:amount_required, field: :amount_cents, message: I18n.t("api.errors.amount_required"))
        end

        if save_checked(@subscription) { check_subscription(@subscription) }
          render json: { subscription: Serialize.subscription(@subscription) }
        else
          render_errors(@subscription)
        end
      end

      # Transactions recorded for earlier charges are not linked to it and
      # stay.
      def destroy
        @subscription.destroy!
        head :no_content
      end

      # Records one payment the way Finance::ProcessSubscriptions does (an
      # expense on the subscription's account and category, then
      # next_charge_on moves one period on), dated `date`, else the due date,
      # or today when paying before it.
      def charge
        reason = chargeable_refusal(@subscription)
        if reason
          return render_unprocessable(:not_chargeable,
            message: I18n.t("api.errors.not_chargeable.#{reason}"), reason: reason)
        end

        date = date_param(:date) || [ @subscription.next_charge_on, Date.current ].min
        transaction = ::Finance::ProcessSubscriptions.charge!(@subscription, date: date)
        render json: {
          subscription: Serialize.subscription(@subscription),
          transaction: Serialize.transaction(transaction)
        }, status: :created
      end

      private

      def set_subscription
        @subscription = current_user.subscriptions.find(params[:id])
      end

      # Only the keys sent change. Ids of another user's account or category
      # are a 404; null finance_category_id leaves it uncategorized.
      def subscription_attributes
        attrs = params.permit(:name, :vendor, :note, :frequency, :color).to_h
        attrs[:amount_cents] = integer_param(:amount_cents) if params.key?(:amount_cents)
        attrs[:active] = required_boolean_param(:active) if params.key?(:active)
        %i[next_charge_on start_date end_date].each { |name| attrs[name] = date_param(name) if params.key?(name) }
        attrs[:account_id] = owned_id_param(current_user.accounts, :account_id) if params.key?(:account_id)
        if params.key?(:finance_category_id)
          attrs[:finance_category_id] = owned_id_param(current_user.finance_categories, :finance_category_id)
        end
        attrs
      end

      # The web form offers expense categories only, and a charge posts an
      # expense, which an income category would refuse
      # (Transaction#category_kind_matches_transaction_kind). Checked on
      # change, so an older row stays editable.
      def check_subscription(subscription)
        check_color(subscription)
        category = subscription.finance_category
        if subscription.will_save_change_to_finance_category_id? && category && category.kind != "expense"
          subscription.errors.add(:finance_category_id, :must_be_expense)
        end
        return unless subscription.will_save_change_to_start_date? || subscription.will_save_change_to_end_date?
        return unless subscription.start_date && subscription.end_date && subscription.end_date < subscription.start_date

        subscription.errors.add(:end_date, :before_start_date)
      end

      def currency_switch?(subscription, previous_currency)
        subscription.will_save_change_to_account_id? && subscription.account &&
          subscription.account.currency.to_s.casecmp(previous_currency).nonzero?
      end

      # ProcessSubscriptions only charges active subscriptions with a due date.
      def chargeable_refusal(subscription)
        return "inactive" unless subscription.active?

        "no_next_charge" if subscription.next_charge_on.nil?
      end

      # start, start + 1 period, start + 2 periods, ...: the first of these
      # after today. Starts counting near today so an old start date does not
      # walk years of weeks.
      def first_charge_on(subscription)
        step = PERIODS[subscription.frequency]
        start = subscription.start_date || Date.current
        return nil unless step

        today = Date.current
        periods = case subscription.frequency
        when "weekly" then (today - start).to_i / 7
        when "monthly" then ((today.year * 12) + today.month) - ((start.year * 12) + start.month) - 1
        else today.year - start.year - 1
        end
        periods = [ periods, 0 ].max
        periods += 1 while start + (step * periods) <= today
        start + (step * periods)
      end

      def totals(active)
        user_currency = current_user.currency.to_s.upcase
        active.group_by { |subscription| subscription.account.currency.to_s.upcase }
              .sort_by { |currency, _| [ currency == user_currency ? 0 : 1, currency ] }
              .map do |currency, subscriptions|
          {
            currency: currency,
            subunit_to_unit: Serialize.subunit_to_unit(currency),
            monthly_cents: subscriptions.sum(&:monthly_amount_cents),
            yearly_cents: subscriptions.sum { |subscription| subscription.yearly_amount_cents.to_i }
          }
        end
      end
    end
  end
end
