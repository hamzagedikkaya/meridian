require "csv"

module Finance
  class TransactionsController < BaseController
    PAGE_LIMIT = 50

    before_action :set_transaction, only: [ :show, :edit, :update, :destroy ]

    def index
      @transactions = current_user.transactions
                                  .includes(:account, :finance_category, :related_account)
                                  .recent
      @transactions = @transactions.where(kind: params[:kind]) if params[:kind].present?
      @transactions = @transactions.where(account_id: params[:account_id]) if params[:account_id].present?
      @transactions = @transactions.where(finance_category_id: params[:category_id]) if params[:category_id].present?
      @transactions = @transactions.between(params[:from], params[:to]) if params[:from].present? && params[:to].present?

      @total_count = @transactions.count
      @page = [ params[:page].to_i, 1 ].max
      @transactions = @transactions.offset((@page - 1) * PAGE_LIMIT).limit(PAGE_LIMIT)
    end

    def show
    end

    def new
      @transaction = current_user.transactions.new(date: Date.current, kind: params[:kind] || "expense")
      load_form_data
    end

    def create
      @transaction = current_user.transactions.new(transaction_params)

      if @transaction.save
        redirect_to finance_transactions_path, notice: t("flash.saved")
      else
        load_form_data
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      load_form_data
    end

    def update
      if @transaction.update(transaction_params)
        redirect_to finance_transactions_path, notice: t("flash.updated")
      else
        load_form_data
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @transaction.destroy
      redirect_to finance_transactions_path, notice: t("flash.deleted")
    end

    def export
      transactions = current_user.transactions.includes(:account, :finance_category).recent
      csv_data = CSV.generate(headers: true) do |csv|
        csv << [ "Date", "Kind", "Account", "Category", "Description", "Amount", "Currency", "Note" ]
        transactions.each do |t|
          csv << [
            t.date,
            t.kind,
            t.account.name,
            t.finance_category&.name,
            t.description,
            (t.amount_cents / 100.0),
            t.account_currency,
            t.note
          ]
        end
      end
      send_data csv_data, filename: "meridian-transactions-#{Date.current.iso8601}.csv", type: "text/csv"
    end

    private

    def set_transaction
      @transaction = current_user.transactions.find(params[:id])
    end

    def load_form_data
      @accounts = user_accounts
      @income_categories  = user_categories("income")
      @expense_categories = user_categories("expense")
    end

    def transaction_params
      params.require(:transaction).permit(
        :account_id, :related_account_id, :finance_category_id,
        :amount, :amount_cents, :kind, :description, :note, :date
      ).tap do |p|
        if p[:amount].present? && p[:amount_cents].blank?
          p[:amount_cents] = (p.delete(:amount).to_f * 100).round
        end
      end
    end
  end
end
