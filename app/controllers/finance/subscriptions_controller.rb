module Finance
  class SubscriptionsController < BaseController
    before_action :set_subscription, only: [ :show, :edit, :update, :destroy ]

    def index
      @active_subs   = current_user.subscriptions.active.includes(:account, :finance_category).order(:next_charge_on)
      @inactive_subs = current_user.subscriptions.inactive.includes(:account, :finance_category)

      @monthly_total_cents = @active_subs.sum { |s| s.frequency == "monthly" ? s.amount_cents : s.yearly_amount_cents / 12 }
      @yearly_total_cents  = @active_subs.sum(&:yearly_amount_cents)
    end

    def show
    end

    def new
      @subscription = current_user.subscriptions.new(active: true, frequency: "monthly", start_date: Date.current, next_charge_on: Date.current + 1.month)
      load_form_data
    end

    def create
      @subscription = current_user.subscriptions.new(subscription_params)
      if @subscription.save
        redirect_to finance_subscriptions_path, notice: t("flash.saved")
      else
        load_form_data
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      load_form_data
    end

    def update
      if @subscription.update(subscription_params)
        redirect_to finance_subscriptions_path, notice: t("flash.updated")
      else
        load_form_data
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @subscription.destroy
      redirect_to finance_subscriptions_path, notice: t("flash.deleted")
    end

    private

    def set_subscription
      @subscription = current_user.subscriptions.find(params[:id])
    end

    def load_form_data
      @accounts = user_accounts
      @categories = user_categories("expense")
    end

    def subscription_params
      params.require(:subscription).permit(
        :name, :vendor, :account_id, :finance_category_id,
        :amount, :amount_cents, :frequency, :next_charge_on,
        :start_date, :end_date, :active, :color, :note
      ).tap do |p|
        if p[:amount].present? && p[:amount_cents].blank?
          p[:amount_cents] = (p.delete(:amount).to_f * subunit_multiplier_for(p[:account_id])).round
        end
      end
    end
  end
end
