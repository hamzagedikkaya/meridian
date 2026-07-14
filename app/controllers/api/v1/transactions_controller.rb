module Api
  module V1
    class TransactionsController < BaseController
      PAGE_LIMIT = 50

      def index
        scope = filtered_scope
        total_count = scope.count
        totals = scope.reorder(nil).group(:kind).sum(:amount_cents)
        page = [ params[:page].to_i, 1 ].max
        transactions = scope.offset((page - 1) * PAGE_LIMIT).limit(PAGE_LIMIT)

        render json: {
          transactions: transactions.map { |transaction| Serialize.transaction(transaction) },
          meta: {
            total_count: total_count,
            page: page,
            page_limit: PAGE_LIMIT,
            filtered_income_cents: totals["income"].to_i,
            filtered_expense_cents: totals["expense"].to_i
          }
        }
      end

      def create
        transaction = current_user.transactions.new(transaction_params)
        if transaction.save
          render json: Serialize.transaction(transaction), status: :created
        else
          render_errors(transaction)
        end
      end

      def update
        transaction = current_user.transactions.find(params[:id])
        if transaction.update(transaction_params)
          render json: Serialize.transaction(transaction)
        else
          render_errors(transaction)
        end
      end

      def destroy
        current_user.transactions.find(params[:id]).destroy
        head :no_content
      end

      private

      def filtered_scope
        scope = current_user.transactions
                            .includes(:account, :finance_category, :related_account)
                            .recent
        scope = scope.where(kind: params[:kind]) if params[:kind].present?
        scope = scope.where(account_id: params[:account_id]) if params[:account_id].present?
        scope = scope.where(finance_category_id: category_filter_ids) if params[:category_id].present?
        scope = scope.between(params[:from], params[:to]) if params[:from].present? && params[:to].present?
        scope
      end

      # A root category filter also matches its subcategories; a child stays exact.
      def category_filter_ids
        category = current_user.finance_categories.find_by(id: params[:category_id])
        return Array(params[:category_id]) unless category

        category.parent_id.nil? ? [ category.id, *category.children.pluck(:id) ] : [ category.id ]
      end

      def transaction_params
        params.permit(
          :kind, :amount_cents, :date, :description, :note,
          :account_id, :finance_category_id, :related_account_id
        ).tap { |permitted| verify_ownership!(permitted) }
      end

      def verify_ownership!(permitted)
        current_user.accounts.find(permitted[:account_id]) if permitted[:account_id].present?
        current_user.accounts.find(permitted[:related_account_id]) if permitted[:related_account_id].present?
        current_user.finance_categories.find(permitted[:finance_category_id]) if permitted[:finance_category_id].present?
      end
    end
  end
end
