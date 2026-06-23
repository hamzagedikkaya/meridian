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

      @top_expense_categories = aggregate_expenses_by_parent(Date.current.beginning_of_month, Date.current).first(5)

      @six_month_series = build_six_month_series
      @category_pie_series = build_category_pie_series
      @pie_range_starts = pie_range_starts
      @active_accounts = current_user.accounts.active.order(:name)
      @currency = current_user.currency
      @budget_statuses = Finance::BudgetStatus.for_user(current_user)
                                              .sort_by { |s| [ { over: 0, warning: 1, under: 2 }[s.state], -s.percent_used ] }
    end

    # Custom-range pie data. Used by the chart's Stimulus controller when the
    # user fills both date inputs below the preset range buttons. The preset
    # ranges (d1/w1/m1/m6/y1) are baked into the page on index for instant
    # switching; this endpoint only fires for the open-ended "between X and Y"
    # case so we avoid one fetch per preset click.
    def category_pie
      from = Date.parse(params[:from].to_s) rescue nil
      to   = Date.parse(params[:to].to_s)   rescue nil
      if from.nil? || to.nil? || from > to
        render json: { error: "invalid_range" }, status: :bad_request
        return
      end
      account_id = params[:account_id].presence
      data = aggregate_expenses_by_parent(from, to, account_id: account_id)
      render json: { pie: data, from: from.iso8601, to: to.iso8601, account_id: account_id }
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

    # One pie dataset per range. Each entry rolls subcategories up under their
    # parent so the pie shows top-level categories only; breakdown carries the
    # per-subcategory amounts for the hover tooltip.
    def build_category_pie_series
      today = Date.current
      {
        d1: aggregate_expenses_by_parent(today, today),
        w1: aggregate_expenses_by_parent(today - 1.week, today),
        m1: aggregate_expenses_by_parent(today - 1.month, today),
        m6: aggregate_expenses_by_parent(today - 6.months, today),
        y1: aggregate_expenses_by_parent(today - 1.year, today)
      }
    end

    # Mirrors the date windows used by build_category_pie_series. The pie's
    # click handler uses these so it can deep-link into /finance/transactions
    # with the same date range the slice represents.
    def pie_range_starts
      today = Date.current
      {
        d1: today.iso8601,
        w1: (today - 1.week).iso8601,
        m1: (today - 1.month).iso8601,
        m6: (today - 6.months).iso8601,
        y1: (today - 1.year).iso8601,
        today: today.iso8601
      }
    end

    # Returns expenses in the given date range, rolled up to the root (parent)
    # category. Each entry: { name:, color:, amount: (cents), breakdown: [{ name:, amount: }] }.
    # The breakdown list contains the per-subcategory amounts (including the
    # parent itself when transactions are tagged directly with it), sorted by
    # amount desc; it's empty when the root has no subcategory activity.
    def aggregate_expenses_by_parent(from, to, account_id: nil)
      scope = current_user.transactions.expense.between(from, to)
      scope = scope.where(account_id: account_id) if account_id.present?
      rows = scope.joins(:finance_category)
                  .group("finance_categories.id")
                  .sum(:amount_cents)
      return [] if rows.empty?

      categories = current_user.finance_categories.where(id: rows.keys).includes(:parent).index_by(&:id)

      buckets = {}
      rows.each do |cat_id, amount|
        cat = categories[cat_id]
        next unless cat
        root = cat.parent || cat
        bucket = (buckets[root.id] ||= { id: root.id, name: root.name, color: root.color, amount: 0, breakdown: [], has_children: false })
        bucket[:amount] += amount
        bucket[:has_children] = true if cat.parent_id.present?
        bucket[:breakdown] << { id: cat.id, name: cat.name, amount: amount, is_root: cat.parent_id.nil? }
      end

      buckets.each_value do |bucket|
        # Only show breakdown when the root actually has subcategory activity —
        # otherwise it's redundant noise in the tooltip.
        bucket[:breakdown] = bucket[:has_children] ? bucket[:breakdown].sort_by { |b| -b[:amount] } : []
        bucket.delete(:has_children)
      end

      buckets.values.sort_by { |b| -b[:amount] }
    end
  end
end
