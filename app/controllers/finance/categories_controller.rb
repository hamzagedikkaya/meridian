module Finance
  class CategoriesController < BaseController
    before_action :set_category, only: [ :edit, :update, :destroy ]

    def index
      roots = current_user.finance_categories.roots.ordered
                          .includes(children: [])
      @income_categories  = roots.select { |c| c.kind == "income" }
      @expense_categories = roots.select { |c| c.kind == "expense" }
      @month_stats = build_month_stats
      @currency = current_user.currency
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

    # { category_id => { count:, total_cents: } } for the current month, in one
    # query. The view rolls subcategory counts/totals into their parent.
    def build_month_stats
      rows = current_user.transactions
                         .between(Date.current.beginning_of_month, Date.current.end_of_month)
                         .where.not(finance_category_id: nil)
                         .group(:finance_category_id)
                         .pluck(:finance_category_id, Arel.sql("COUNT(*)"), Arel.sql("COALESCE(SUM(amount_cents), 0)"))
      rows.to_h { |id, count, total| [ id, { count: count.to_i, total_cents: total.to_i } ] }
    end
  end
end
