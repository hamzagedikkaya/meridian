module Api
  module V1
    module Finance
      class DashboardController < BaseController
        UNCATEGORIZED_COLOR = "#6E6A64"

        def show
          render json: {
            currency: current_user.currency,
            subunit_to_unit: Serialize.subunit_to_unit(current_user.currency),
            month: month_summary,
            year: year_summary,
            totals_by_currency: totals_by_currency,
            six_month_series: six_month_series,
            spend_cumulative_cents: spend_cumulative_cents,
            reference_cumulative_cents: reference_cumulative_cents,
            pie: pie,
            budgets: budgets,
            upcoming_subscriptions: upcoming_subscriptions,
            recent_transactions: recent_transactions
          }
        end

        private

        # The totals below (month, year, six_month_series, the cumulative
        # series, pie) count only transactions on accounts in the user's
        # currency, so minor units of different currencies are never added
        # up. totals_by_currency has the month and year of every currency.
        def own_transactions
          @own_transactions ||= current_user.transactions.where(
            account_id: current_user.accounts.where("UPPER(accounts.currency) = ?", own_currency).select(:id)
          )
        end

        def own_currency
          current_user.currency.to_s.upcase
        end

        def month_summary
          income  = own_transactions.this_month.income.sum(:amount_cents)
          expense = own_transactions.this_month.expense.sum(:amount_cents)
          { income_cents: income, expense_cents: expense, net_cents: income - expense }
        end

        def year_summary
          {
            income_cents: own_transactions.this_year.income.sum(:amount_cents),
            expense_cents: own_transactions.this_year.expense.sum(:amount_cents)
          }
        end

        # Month and year totals per account currency: the user's currency
        # first (the same numbers as month and year), then every other
        # currency of an active account or of a transaction this year, by
        # code. Nothing is converted.
        def totals_by_currency
          month = sums_by_currency(Date.current.all_month)
          year = sums_by_currency(Date.current.all_year)
          others = current_user.accounts.active.distinct.pluck(Arel.sql("UPPER(accounts.currency)")) +
                   year.keys.map(&:first)
          ([ own_currency ] + (others.uniq - [ own_currency ]).sort).map do |currency|
            income = month[[ currency, "income" ]].to_i
            expense = month[[ currency, "expense" ]].to_i
            {
              currency: currency,
              subunit_to_unit: Serialize.subunit_to_unit(currency),
              month: { income_cents: income, expense_cents: expense, net_cents: income - expense },
              year: { income_cents: year[[ currency, "income" ]].to_i, expense_cents: year[[ currency, "expense" ]].to_i }
            }
          end
        end

        # {[CURRENCY, kind] => cents} for income and expense dated in +range+.
        def sums_by_currency(range)
          current_user.transactions.joins(:account)
                      .where(kind: %w[income expense], date: range)
                      .group(Arel.sql("UPPER(accounts.currency)"), "transactions.kind")
                      .sum(:amount_cents)
        end

        # This month's expenses added up day by day: one element per day
        # from the 1st to today, the last one today's running total.
        # Expenses dated later this month are counted on today, so the last
        # element always equals month.expense_cents.
        def spend_cumulative_cents
          today = Date.current
          daily = daily_expenses(today.all_month)
          series = cumulative(daily, today.beginning_of_month..today)
          series[-1] += daily.sum { |day, cents| day > today ? cents : 0 }
          series
        end

        # Last month's expenses added up day by day, one element for each of
        # its days; the last one is last month's total.
        def reference_cumulative_cents
          last_month = Date.current.prev_month.all_month
          cumulative(daily_expenses(last_month), last_month)
        end

        def daily_expenses(range)
          own_transactions.expense.where(date: range).group(:date).sum(:amount_cents)
        end

        def cumulative(daily, days)
          running = 0
          days.map { |day| running += daily[day].to_i }
        end

        def six_month_series
          start_month = 5.months.ago.beginning_of_month.to_date
          months = (0..5).map { |i| start_month + i.months }
          incomes  = monthly_sums(own_transactions.income, start_month)
          expenses = monthly_sums(own_transactions.expense, start_month)

          {
            labels: months.map { |month| month.strftime("%Y-%m") },
            income_cents: months.map { |month| incomes[month] || 0 },
            expense_cents: months.map { |month| expenses[month] || 0 }
          }
        end

        # `date` is a calendar date, not an instant: time_zone: false stops
        # groupdate from shifting it through the user's zone (west of UTC the
        # 1st of a month would be counted in the previous month).
        def monthly_sums(scope, start_month)
          scope.between(start_month, Date.current.end_of_month)
               .group_by_month(:date, time_zone: false).sum(:amount_cents)
        end

        # This month's expenses rolled up to root categories (a cents-only
        # variant of the web dashboard's aggregate_expenses_by_parent), plus a
        # bucket for expenses without a category, such as every quick-capture
        # expense. The window is month's, the whole calendar month, so the
        # slices add up to month.expense_cents.
        def pie
          rows = own_transactions.expense.this_month
                             .group(:finance_category_id)
                             .sum(:amount_cents)
          return [] if rows.empty?

          categories = current_user.finance_categories.where(id: rows.keys.compact).includes(:parent).index_by(&:id)

          buckets = {}
          uncategorized_cents = 0
          rows.each do |category_id, amount_cents|
            category = categories[category_id]
            # No category (or, on rows older than the ownership checks,
            # another user's).
            unless category
              uncategorized_cents += amount_cents
              next
            end

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

          slices = buckets.values
          slices << uncategorized_slice(uncategorized_cents) if uncategorized_cents.positive?
          slices.sort_by { |slice| [ -slice[:amount_cents], slice[:id] ] }
        end

        # id 0 is never a category's. A client that does not read the
        # `uncategorized` flag still draws it as a slice of its own.
        def uncategorized_slice(amount_cents)
          {
            id: 0, name: I18n.t("api.finance.uncategorized"), color: UNCATEGORIZED_COLOR,
            amount_cents: amount_cents, breakdown: [], uncategorized: true
          }
        end

        # Same entries as GET /budgets, ordered over budget first.
        def budgets
          ::Finance::BudgetStatus.for_user(current_user)
                                 .sort_by { |status| [ { over: 0, warning: 1, under: 2 }[status.state], -status.percent_used ] }
                                 .map { |status| Serialize.budget(status) }
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
