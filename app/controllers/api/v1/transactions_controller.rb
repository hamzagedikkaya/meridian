module Api
  module V1
    class TransactionsController < BaseController
      include TextMatching

      PAGE_LIMIT = 50
      # Far past any real history (5 million transactions); a larger page
      # would overflow the OFFSET.
      MAX_PAGE = 100_000

      def index
        scope = filtered_scope
        total_count = scope.count
        totals = scope.reorder(nil).group(:kind).sum(:amount_cents)
        page = lenient_integer_param(:page, range: 1..MAX_PAGE) || 1
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

      def show
        transaction = current_user.transactions.includes(:account, :finance_category, :related_account).find(params[:id])
        render json: { transaction: Serialize.transaction(transaction).merge(linked_json(transaction)) }
      end

      # finance_category_id may be omitted or null: an uncategorized
      # transaction (the model's belongs_to is optional).
      def create
        transaction = current_user.transactions.new(transaction_params)
        if save_checked(transaction) { check_transfer(transaction) }
          render json: Serialize.transaction(transaction), status: :created
        else
          render_errors(transaction)
        end
      end

      def update
        transaction = current_user.transactions.find(params[:id])
        transaction.assign_attributes(transaction_params)
        if save_checked(transaction) { check_transfer(transaction) }
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
        scope = scope.where(kind: filter_value(:kind)) if filter_value(:kind)
        scope = account_filter(scope) if filter_value(:account_id)
        if filter_value(:category_id) == "none"
          scope = scope.where(finance_category_id: nil)
        elsif filter_value(:category_id)
          scope = scope.where(finance_category_id: category_filter_ids)
        end
        scope = scope.between(filter_value(:from), filter_value(:to)) if filter_value(:from) && filter_value(:to)
        text_filter(scope)
      end

      # A filter's value: a non-blank string or number. A list or an object
      # is dropped, as if it had not been sent (contract 1.1).
      def filter_value(name)
        value = params[name]
        value = value.to_s if value.is_a?(Integer)
        value if value.is_a?(String) && value.present?
      end

      # q: the description or the note contains the text (TextMatching:
      # any case, Turkish letters included). Absent or blank applies no
      # filter; a list or an object is 422 invalid_parameter.
      def text_filter(scope)
        query = params[:q]
        return scope if query.nil?
        raise InvalidParameter, :q unless query.is_a?(String)
        return scope if query.strip.empty?

        table = ::Transaction.arel_table
        scope.where(text_match([ table[:description], table[:note] ], query.strip))
      end

      # The web's linked counter-transaction (Finance::TransactionsController
      # #save_with_linked), shown like the web's show page: this one's parent,
      # or the child created with it. Deleting a parent also deletes its
      # child (dependent: :destroy); deleting a child leaves the parent.
      def linked_json(transaction)
        linked = transaction.parent_transaction_id &&
          current_user.transactions.includes(:account).find_by(id: transaction.parent_transaction_id)
        relation = "parent"
        unless linked
          linked = current_user.transactions.includes(:account).where(parent_transaction_id: transaction.id).order(:id).first
          relation = "child"
        end

        {
          parent_transaction_id: transaction.parent_transaction_id,
          linked: linked && {
            id: linked.id,
            kind: linked.kind,
            amount_cents: linked.amount_cents,
            date: linked.date,
            description: linked.description,
            account: Serialize.account_brief(linked.account),
            relation: relation
          }
        }
      end

      # The account's own transactions; with include_incoming_transfers=true
      # also other accounts' transfers into it, which move its balance too
      # (Account#balance_cents) but are stored on the source account.
      def account_filter(scope)
        own = scope.where(account_id: filter_value(:account_id))
        return own unless boolean_param(:include_incoming_transfers)

        own.or(scope.where(related_account_id: filter_value(:account_id), kind: "transfer"))
      end

      # The destination of a transfer must be another account in the same
      # currency: the balance math credits it with the source's minor units
      # as they are (Account#balance_cents), so 100.00 TRY sent to a GAU
      # account would add 10,000 grams. A move between currencies is an
      # expense on one account and an income on the other. Checked only when
      # the kind or an account changes, so older rows stay editable. (The web
      # has no transfer form whose rules this could mirror.)
      def check_transfer(transaction)
        return unless transaction.kind == "transfer" && transaction.account && transaction.related_account
        return unless transaction.will_save_change_to_kind? || transaction.will_save_change_to_account_id? ||
                      transaction.will_save_change_to_related_account_id?

        if transaction.related_account_id == transaction.account_id
          transaction.errors.add(:related_account_id, :same_account)
        elsif transaction.related_account.currency.to_s.casecmp(transaction.account.currency.to_s).nonzero?
          transaction.errors.add(:related_account_id, :currency_mismatch)
        end
      end

      # A root category filter also matches its subcategories; a child stays exact.
      def category_filter_ids
        category = current_user.finance_categories.find_by(id: filter_value(:category_id))
        return [ filter_value(:category_id) ] unless category

        category.parent_id.nil? ? [ category.id, *category.children.pluck(:id) ] : [ category.id ]
      end

      # The ids are the user's (404 otherwise) and whole numbers (422
      # invalid_parameter otherwise); null or "" clears an optional one.
      def transaction_params
        attrs = params.permit(:kind, :amount_cents, :date, :description, :note).to_h
        attrs[:account_id] = owned_id_param(current_user.accounts, :account_id) if params.key?(:account_id)
        attrs[:related_account_id] = owned_id_param(current_user.accounts, :related_account_id) if params.key?(:related_account_id)
        if params.key?(:finance_category_id)
          attrs[:finance_category_id] = owned_id_param(current_user.finance_categories, :finance_category_id)
        end
        attrs
      end
    end
  end
end
