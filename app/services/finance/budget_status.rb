module Finance
  # Computes month-to-date status for a budget: how much of the cap is spent,
  # what remains, and — via a run-rate projection against how far into the month
  # we are — whether the user is on track or pacing toward an overspend. Pure
  # value object so the dashboard card and the budgets page share one source of
  # truth; no external data, all derived from the user's own transactions.
  class BudgetStatus
    # Build a status per budget for `user` as of `on`, with month-to-date spend
    # rolled from subcategories up to each budgeted root category.
    def self.for_user(user, on: Date.current)
      actuals = month_actuals(user, on.beginning_of_month, on)
      user.budgets.includes(:finance_category).ordered.map do |budget|
        new(budget: budget, spent_cents: actuals[budget.finance_category_id] || 0, on: on)
      end
    end

    # { root_category_id => spent_cents } for the window, summing each
    # transaction's category (or its parent) into the root. Mirrors the
    # dashboard spending-breakdown rollup.
    def self.month_actuals(user, from, to)
      rows = user.transactions.expense.between(from, to)
                 .where.not(finance_category_id: nil)
                 .group(:finance_category_id).sum(:amount_cents)
      return {} if rows.empty?

      categories = user.finance_categories.where(id: rows.keys).index_by(&:id)
      totals = Hash.new(0)
      rows.each do |cat_id, cents|
        cat = categories[cat_id]
        next unless cat

        totals[cat.parent_id || cat.id] += cents
      end
      totals
    end

    attr_reader :budget, :spent_cents, :on

    def initialize(budget:, spent_cents:, on: Date.current)
      @budget = budget
      @spent_cents = spent_cents.to_i
      @on = on
    end

    def category = budget.finance_category
    def color = budget.color.presence || category.color
    def limit_cents = budget.monthly_limit_cents
    def remaining_cents = limit_cents - spent_cents
    def over? = spent_cents > limit_cents
    def over_by_cents = over? ? spent_cents - limit_cents : 0

    # Uncapped, for the "93% used" label; bar_percent is the clamped width.
    def percent_used
      return 0 if limit_cents.zero?
      (spent_cents.to_f / limit_cents * 100).round
    end

    def bar_percent = [ percent_used, 100 ].min

    def days_in_month = on.end_of_month.day
    def day_of_month  = on.day

    # Share of the month elapsed — the marker the spend bar is measured against.
    def pace_percent = (day_of_month.to_f / days_in_month * 100).round

    # Straight-line projection of month-end spend at the current run rate.
    def projected_cents
      return spent_cents if day_of_month.zero?
      (spent_cents.to_f / day_of_month * days_in_month).round
    end

    def will_overspend? = !over? && projected_cents > limit_cents

    def state
      return :over if over?
      return :warning if will_overspend?
      :under
    end

    def on_track? = state == :under
  end
end
