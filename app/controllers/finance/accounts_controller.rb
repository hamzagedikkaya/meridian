module Finance
  class AccountsController < BaseController
    before_action :set_account, only: [ :show, :edit, :update, :destroy ]

    def index
      @accounts = current_user.accounts.order(archived_at: :asc, name: :asc)
    end

    def show
      @transactions = @account.transactions.includes(:finance_category).recent.limit(50)
    end

    def new
      @account = current_user.accounts.new(currency: current_user.currency)
    end

    def create
      @account = current_user.accounts.new(account_params)
      if @account.save
        redirect_to finance_accounts_path, notice: t("flash.saved")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    # The currency stays once something is recorded on the account, as in
    # the API (Account#currency_locked?): 100.00 TRY would otherwise become
    # 10,000 grams of GAU. Letter case alone is not a change.
    def update
      @account.assign_attributes(account_params)
      if @account.currency.to_s.casecmp(@account.currency_in_database.to_s).nonzero? && @account.currency_locked?
        @account.errors.add(:base, t("api.errors.currency_locked"))
        render :edit, status: :unprocessable_entity
      elsif @account.save
        redirect_to finance_accounts_path, notice: t("flash.updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @account.destroy
      redirect_to finance_accounts_path, notice: t("flash.deleted")
    end

    private

    def set_account
      @account = current_user.accounts.find(params[:id])
    end

    def account_params
      params.require(:account).permit(:name, :account_type, :currency, :initial_balance_cents, :color, :archived_at)
    end
  end
end
