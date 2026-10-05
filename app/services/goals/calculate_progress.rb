module Goals
  # A goal's progress and the status it implies. Every read recomputes both:
  # a goal that is not abandoned is achieved exactly when its value reaches
  # the target, so "abandoned" is the only status that sticks on its own.
  class CalculateProgress
    def self.call(goal)
      new(goal).call
    end

    def initialize(goal)
      @goal = goal
    end

    # Where the value comes from:
    #   "account" - the linked account's balance (financial goal)
    #   "income"  - the user's income, all time (financial goal, no account)
    #   "habit"   - the linked habit's completed days (habit goal)
    #   "manual"  - what the user logs (custom goal, or a habit goal with no
    #               habit linked)
    def source
      case @goal.target_type
      when "financial" then @goal.related.is_a?(Account) ? "account" : "income"
      when "habit"     then @goal.related.is_a?(Habit) ? "habit" : "manual"
      else                  "manual"
      end
    end

    # Reads the goal as it is in memory, so it also works for unsaved
    # changes (a new link, a new target type).
    def value
      case source
      when "account", "income" then financial_progress
      when "habit"             then habit_progress
      else                          @goal.current_value
      end
    end

    def status_for(value)
      return "abandoned" if @goal.status == "abandoned"

      value.to_f >= @goal.target_value.to_f ? "achieved" : "active"
    end

    # Stores the recomputed value and status without validations or
    # callbacks. A read that changes neither writes nothing.
    def call
      value = self.value
      status = status_for(value)
      @goal.update_columns(current_value: value, status: status) unless @goal.current_value == value && @goal.status == status
      value
    end

    private

    def financial_progress
      if @goal.related.is_a?(Account)
        account = @goal.related
        account.balance_cents / CurrencyUnit.subunit_to_unit(account.currency).to_f
      else
        user_income_cents / CurrencyUnit.subunit_to_unit(@goal.user.currency).to_f
      end
    end

    # All-time income on the accounts in the user's own currency, as the
    # finance dashboard counts it: another currency's minor units (grams of
    # GAU, US cents) are not the user's and are not converted.
    def user_income_cents
      user = @goal.user
      accounts = user.accounts.where("UPPER(accounts.currency) = ?", user.currency.to_s.upcase)
      user.transactions.income.where(account_id: accounts.select(:id)).sum(:amount_cents)
    end

    def habit_progress
      @goal.related.habit_logs.where(completed: true).count
    end
  end
end
