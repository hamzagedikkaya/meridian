module Finance
  class CategoriesController < BaseController
    before_action :set_category, only: [ :edit, :update, :destroy ]

    def index
      @income_categories  = current_user.finance_categories.income.roots.ordered
      @expense_categories = current_user.finance_categories.expense.roots.ordered
    end

    def new
      @category = current_user.finance_categories.new(kind: params[:kind] || "expense")
    end

    def create
      @category = current_user.finance_categories.new(category_params)
      if @category.save
        redirect_to finance_categories_path, notice: t("flash.saved")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @category.update(category_params)
        redirect_to finance_categories_path, notice: t("flash.updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @category.destroy
      redirect_to finance_categories_path, notice: t("flash.deleted")
    end

    private

    def set_category
      @category = current_user.finance_categories.find(params[:id])
    end

    def category_params
      params.require(:finance_category).permit(:name, :color, :icon, :kind, :parent_id, :position)
    end
  end
end
