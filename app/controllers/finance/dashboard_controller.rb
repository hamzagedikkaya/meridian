module Finance
  class DashboardController < BaseController
    def index
      @month_income  = current_user.transactions.this_month.income.sum(:amount_cents)
      @month_expense = current_user.transactions.this_month.expense.sum(:amount_cents)
      @month_net     = @month_income - @month_expense

      @year_income  = current_user.transactions.this_year.income.sum(:amount_cents)
      @year_expense = current_user.transactions.this_year.expense.sum(:amount_cents)

      @recent_transactions = current_user.transactions
                                         .includes(:account, :finance_category)
                                         .recent.limit(8)

      @upcoming_subscriptions = current_user.subscriptions.upcoming.includes(:account).limit(5)

      @top_expense_categories = current_user.transactions
                                            .this_month.expense
                                            .joins(:finance_category)
                                            .group("finance_categories.name", "finance_categories.color")
                                            .sum(:amount_cents)
                                            .sort_by { |_, v| -v }
                                            .first(5)

      @six_month_series = build_six_month_series
      @category_pie_series = build_category_pie_series
      @active_accounts = current_user.accounts.active.order(:name)
      @currency = current_user.currency
    end

    private

    def build_six_month_series
      start_date = 5.months.ago.beginning_of_month.to_date
      months = (0..5).map { |i| (start_date + i.months).beginning_of_month }

      incomes  = current_user.transactions.income.between(months.first, Date.current.end_of_month)
                             .group_by_month(:date).sum(:amount_cents)
      expenses = current_user.transactions.expense.between(months.first, Date.current.end_of_month)
                             .group_by_month(:date).sum(:amount_cents)

      {
        labels: months.map { |m| m.strftime("%b") },
        income: months.map { |m| (incomes[m] || 0) / 100.0 },
        expense: months.map { |m| (expenses[m] || 0) / 100.0 }
      }
    end

    # One pie dataset per range. Each entry: { name:, color:, amount: } in cents.
    def build_category_pie_series
      today = Date.current
      ranges = {
        m1: today - 1.month,
        m6: today - 6.months,
        y1: today - 1.year
      }

      ranges.transform_values do |from|
        rows = current_user.transactions.expense
                           .between(from, today)
                           .joins(:finance_category)
                           .group("finance_categories.name", "finance_categories.color")
                           .sum(:amount_cents)
        rows.sort_by { |_, v| -v }.map { |(name, color), amount| { name: name, color: color, amount: amount } }
      end
    end
  end
end
