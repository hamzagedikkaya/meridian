module Finance
  class BudgetsController < BaseController
    before_action :set_budget, only: [ :edit, :update, :destroy ]

    def index
      @statuses = Finance::BudgetStatus.for_user(current_user)
      @currency = current_user.currency
    end

    def new
      @budget = current_user.budgets.new
    end

    def create
      @budget = current_user.budgets.new(budget_params)
      if amount_precise?(@budget) && @budget.save
        redirect_to finance_budgets_path, notice: t("flash.saved")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      @budget.assign_attributes(budget_params)
      if amount_precise?(@budget) && @budget.save
        redirect_to finance_budgets_path, notice: t("flash.updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @budget.destroy
      redirect_to finance_budgets_path, notice: t("flash.deleted")
    end

    # Expense root categories available to budget — excludes those already
    # budgeted (except the one being edited, so its picker stays valid).
    helper_method :budgetable_categories

    def budgetable_categories
      taken = current_user.budgets.where.not(id: @budget&.id).pluck(:finance_category_id)
      current_user.finance_categories.expense.roots.ordered.where.not(id: taken)
    end

    private

    def set_budget
      @budget = current_user.budgets.find(params[:id])
    end

    # The form's decimal :monthly_limit in minor units of the user's currency
    # (100 for TRY/USD, 1 for GAU gram-gold), not a hardcoded *100. A
    # fraction of the smallest unit (1.5 grams) is refused by
    # #amount_precise?, not rounded into another limit.
    def budget_params
      permitted = params.require(:budget).permit(:finance_category_id, :color, :monthly_limit)
      if permitted[:monthly_limit].present?
        permitted[:monthly_limit_cents] = minor_units_in(permitted.delete(:monthly_limit), current_user.currency)
      end
      permitted
    end
  end
end
