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
        redirect_to finance_accounts_path, notice: "Account created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @account.update(account_params)
        redirect_to finance_accounts_path, notice: "Account updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @account.destroy
      redirect_to finance_accounts_path, notice: "Account deleted."
    end

    private

    def set_account
      @account = current_user.accounts.find(params[:id])
    end

    def account_params
      params.require(:account).permit(:name, :account_type, :currency, :initial_balance_cents, :color, :icon, :archived_at)
    end
  end
end
