module Api
  module V1
    class FinanceCategoriesController < BaseController
      before_action :set_category, only: [ :show, :update, :destroy ]

      def index
        categories = current_user.finance_categories.ordered
        render json: { categories: categories.map { |category| Serialize.category(category) } }
      end

      # The category plus what a delete would touch and whether its kind can
      # still change.
      def show
        render json: { category: Serialize.category(@category).merge(usage_json(@category)) }
      end

      # kind defaults to the parent's, otherwise to expense (the web form's
      # default). The model checks the rest: name unique per parent ignoring
      # case, a parent that is the user's root category of the same kind.
      def create
        category = current_user.finance_categories.new
        category.assign_attributes(category_attributes)
        category.kind = category.parent.kind if category.parent && !params.key?(:kind)

        if save_checked(category) { check_color(category) }
          render json: { category: Serialize.category(category) }, status: :created
        else
          render_errors(category)
        end
      end

      def update
        @category.assign_attributes(category_attributes)
        if @category.will_save_change_to_kind? && in_use?(@category)
          return render_unprocessable(:kind_locked, field: :kind, message: I18n.t("api.errors.kind_locked"))
        end

        if save_checked(@category) { check_category(@category) }
          render json: { category: Serialize.category(@category) }
        else
          render_errors(@category)
        end
      end

      # The web's delete, through the model's dependent options, in one
      # transaction: subcategories are deleted too; the transactions and
      # subscriptions of the category and its subcategories stay, without a
      # category; their budgets are deleted.
      def destroy
        @category.destroy!
        head :no_content
      end

      private

      def set_category
        @category = current_user.finance_categories.find(params[:id])
      end

      # parent_id null (or "") makes the category a root; another user's id
      # is a 404, as for the ids POST /transactions takes.
      def category_attributes
        attrs = params.permit(:name, :kind, :color).to_h
        attrs[:position] = required_integer_param(:position) if params.key?(:position)
        if params.key?(:parent_id)
          attrs[:parent_id] = owned_id_param(current_user.finance_categories, :parent_id)
        end
        attrs
      end

      # A kind change would strand rows of the old kind: its transactions
      # would fail category_kind_matches_transaction_kind on their next edit,
      # its subcategories their parent check, its budget the expense-only
      # rule, and its subscriptions would post expenses into an income
      # category.
      def in_use?(category)
        category.children.exists? || category.transactions.exists? ||
          category.budgets.exists? || category.subscriptions.exists?
      end

      # Budgets sit on root categories (Budget#category_is_expense_root), and
      # BudgetStatus rolls a subcategory's spend into its parent, so a
      # budgeted category moved under a parent would never count again.
      def check_category(category)
        check_color(category)
        return unless category.will_save_change_to_parent_id? && category.parent_id && category.budgets.exists?

        category.errors.add(:parent_id, :has_budget)
      end

      def usage_json(category)
        ids = [ category.id, *category.children.ids ]
        {
          children_count: ids.size - 1,
          transactions_count: current_user.transactions.where(finance_category_id: ids).count,
          subscriptions_count: current_user.subscriptions.where(finance_category_id: ids).count,
          budgets_count: current_user.budgets.where(finance_category_id: ids).count,
          budget_id: current_user.budgets.where(finance_category_id: category.id).pick(:id),
          kind_editable: !in_use?(category)
        }
      end
    end
  end
end
