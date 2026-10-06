module Api
  module V1
    class BudgetsController < BaseController
      before_action :set_budget, only: [ :update, :destroy ]

      # Month-to-date status per budget, in the web budgets page's order
      # (category position, then name). Budgets are in the user's currency.
      def index
        render json: {
          currency: current_user.currency,
          subunit_to_unit: Serialize.subunit_to_unit(current_user.currency),
          as_of: Date.current,
          budgets: ::Finance::BudgetStatus.for_user(current_user).map { |status| Serialize.budget(status) },
          budgetable_category_ids: budgetable_category_ids
        }
      end

      # The model's rules: an expense root category of the user's, one budget
      # per category, a limit above 0.
      def create
        save_budget(current_user.budgets.new, :created)
      end

      def update
        save_budget(@budget, :ok)
      end

      def destroy
        @budget.destroy!
        head :no_content
      end

      private

      def set_budget
        @budget = current_user.budgets.find(params[:id])
      end

      def save_budget(budget, status)
        budget.assign_attributes(budget_attributes)
        if save_checked(budget) { check_color(budget, allow_blank: true) }
          render json: { budget: Serialize.budget(status_for(budget)) }, status: status
        else
          render_errors(budget)
        end
      rescue ActiveRecord::RecordNotUnique
        # Two requests budgeting one category at once: the unique index
        # catches what the uniqueness validation could not.
        budget.errors.add(:finance_category_id, :taken, value: budget.finance_category_id)
        render_errors(budget)
      end

      # The limit is in minor units of the user's currency, never a decimal.
      # color null (or "") drops the budget's own color for its category's;
      # a list or an object is dropped, as if it had not been sent.
      def budget_attributes
        attrs = {}
        attrs[:monthly_limit_cents] = integer_param(:monthly_limit_cents) if params.key?(:monthly_limit_cents)
        attrs[:color] = params[:color].presence if params.key?(:color) && (params[:color].nil? || params[:color].is_a?(String))
        if params.key?(:finance_category_id)
          attrs[:finance_category_id] = owned_id_param(current_user.finance_categories, :finance_category_id)
        end
        attrs
      end

      def status_for(budget)
        today = Date.current
        spent = ::Finance::BudgetStatus.month_actuals(current_user, today.beginning_of_month, today)
        ::Finance::BudgetStatus.new(budget: budget, spent_cents: spent[budget.finance_category_id], on: today)
      end

      # Expense root categories without a budget: the web form's picker
      # (Finance::BudgetsController#budgetable_categories).
      def budgetable_category_ids
        current_user.finance_categories.expense.roots.ordered
                    .where.not(id: current_user.budgets.select(:finance_category_id)).ids
      end
    end
  end
end
