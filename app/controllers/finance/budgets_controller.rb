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
      if @budget.save
        redirect_to finance_budgets_path, notice: t("flash.saved")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @budget.update(budget_params)
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

    # Convert the form's decimal :monthly_limit into cents using the user's
    # currency subunit (100 for TRY/USD, 1 for GAU gram-gold) instead of a
    # hardcoded *100.
    def budget_params
      permitted = params.require(:budget).permit(:finance_category_id, :color, :monthly_limit)
      if permitted[:monthly_limit].present?
        permitted[:monthly_limit_cents] = (permitted.delete(:monthly_limit).to_f * user_subunit).round
      end
      permitted
    end

    def user_subunit
      Money::Currency.find(current_user.currency)&.subunit_to_unit || Money.default_currency.subunit_to_unit
    end
  end
end
