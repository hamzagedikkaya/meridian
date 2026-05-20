module Finance
  class ReportsController < BaseController
    def index
      from = (params[:from].presence || Date.current.beginning_of_month).to_date
      to   = (params[:to].presence   || Date.current.end_of_month).to_date

      scope = current_user.transactions.between(from, to)
      @from = from
      @to   = to

      @by_category = scope.expense.joins(:finance_category)
                          .group("finance_categories.name", "finance_categories.color")
                          .sum(:amount_cents)
                          .sort_by { |_, v| -v }

      @by_account = scope.expense.joins(:account)
                         .group("accounts.name", "accounts.color")
                         .sum(:amount_cents)
                         .sort_by { |_, v| -v }

      @daily_totals = scope.expense.group_by_day(:date).sum(:amount_cents)
    end
  end
end
