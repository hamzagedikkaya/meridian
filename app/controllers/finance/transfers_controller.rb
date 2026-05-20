module Finance
  class TransfersController < BaseController
    def new
      @accounts = user_accounts
    end

    def create
      from = current_user.accounts.find(params[:from_account_id])
      to   = current_user.accounts.find(params[:to_account_id])
      amount_cents = (params[:amount].to_f * 100).round

      result = ::Finance::TransferBetweenAccounts.call(
        user: current_user,
        from_account: from,
        to_account: to,
        amount_cents: amount_cents,
        date: params[:date].presence || Date.current,
        description: params[:description].presence,
        note: params[:note].presence
      )

      if result.success?
        redirect_to finance_transactions_path, notice: "Transfer recorded."
      else
        flash.now[:alert] = result.error
        @accounts = user_accounts
        render :new, status: :unprocessable_entity
      end
    end
  end
end
