module Api
  module V1
    module Finance
      class DashboardController < BaseController
        def show
          render json: {
            currency: current_user.currency,
            subunit_to_unit: Serialize.subunit_to_unit(current_user.currency),
            month: month_summary,
            year: year_summary,
            six_month_series: six_month_series,
            pie: pie,
            budgets: budgets,
            upcoming_subscriptions: upcoming_subscriptions,
            recent_transactions: recent_transactions
          }
        end

        private

        def month_summary
          income  = current_user.transactions.this_month.income.sum(:amount_cents)
          expense = current_user.transactions.this_month.expense.sum(:amount_cents)
          { income_cents: income, expense_cents: expense, net_cents: income - expense }
        end

        def year_summary
          {
            income_cents: current_user.transactions.this_year.income.sum(:amount_cents),
            expense_cents: current_user.transactions.this_year.expense.sum(:amount_cents)
          }
        end

        def six_month_series
          start_month = 5.months.ago.beginning_of_month.to_date
          months = (0..5).map { |i| start_month + i.months }
          incomes  = monthly_sums(current_user.transactions.income, start_month)
          expenses = monthly_sums(current_user.transactions.expense, start_month)

          {
            labels: months.map { |month| month.strftime("%Y-%m") },
            income_cents: months.map { |month| incomes[month] || 0 },
            expense_cents: months.map { |month| expenses[month] || 0 }
          }
        end

        def monthly_sums(scope, start_month)
          scope.between(start_month, Date.current.end_of_month).group_by_month(:date).sum(:amount_cents)
        end

        # Current-month expenses rolled up to root categories, cents-only
        # variant of the web dashboard's aggregate_expenses_by_parent.
        def pie
          rows = current_user.transactions.expense
                             .between(Date.current.beginning_of_month, Date.current)
                             .joins(:finance_category)
                             .group("finance_categories.id")
                             .sum(:amount_cents)
          return [] if rows.empty?

          categories = current_user.finance_categories.where(id: rows.keys).includes(:parent).index_by(&:id)

          buckets = {}
          rows.each do |category_id, amount_cents|
            category = categories[category_id]
            next unless category

            root = category.parent || category
            bucket = (buckets[root.id] ||= {
              id: root.id, name: root.name, color: root.color,
              amount_cents: 0, breakdown: [], has_children: false
            })
            bucket[:amount_cents] += amount_cents
            bucket[:has_children] = true if category.parent_id.present?
            bucket[:breakdown] << {
              id: category.id, name: category.name,
              amount_cents: amount_cents, is_root: category.parent_id.nil?
            }
          end

          buckets.each_value do |bucket|
            bucket[:breakdown] = bucket[:has_children] ? bucket[:breakdown].sort_by { |entry| -entry[:amount_cents] } : []
            bucket.delete(:has_children)
          end

          buckets.values.sort_by { |bucket| -bucket[:amount_cents] }
        end

        def budgets
          ::Finance::BudgetStatus.for_user(current_user)
                                 .sort_by { |status| [ { over: 0, warning: 1, under: 2 }[status.state], -status.percent_used ] }
                                 .map do |status|
            {
              category: { id: status.category.id, name: status.category.name },
              color: status.color,
              limit_cents: status.limit_cents,
              spent_cents: status.spent_cents,
              remaining_cents: status.remaining_cents,
              percent_used: status.percent_used,
              pace_percent: status.pace_percent,
              projected_cents: status.projected_cents,
              state: status.state
            }
          end
        end

        def upcoming_subscriptions
          current_user.subscriptions.upcoming.includes(:account).limit(5).map do |subscription|
            {
              id: subscription.id,
              name: subscription.name,
              amount_cents: subscription.amount_cents,
              frequency: subscription.frequency,
              next_charge_on: subscription.next_charge_on,
              account: Serialize.account_brief(subscription.account)
            }
          end
        end

        def recent_transactions
          current_user.transactions
                      .includes(:account, :finance_category, :related_account)
                      .recent.limit(8)
                      .map { |transaction| Serialize.transaction(transaction) }
        end
      end
    end
  end
end
