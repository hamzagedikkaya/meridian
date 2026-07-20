module Goals
  class CalculateProgress
    def self.call(goal)
      new(goal).call
    end

    def initialize(goal)
      @goal = goal
    end

    def call
      value = case @goal.target_type
      when "financial" then financial_progress
      when "habit"     then habit_progress
      else                  @goal.current_value
      end

      status = value.to_f >= @goal.target_value.to_f ? "achieved" : "active"
      @goal.update_columns(current_value: value, status: @goal.status == "abandoned" ? "abandoned" : status)
      value
    end

    private

    def financial_progress
      if @goal.related.is_a?(Account)
        account = @goal.related
        subunit = Money::Currency.find(account.currency)&.subunit_to_unit || 100
        account.balance_cents / subunit.to_f
      else
        subunit = Money::Currency.find(@goal.user.currency)&.subunit_to_unit || 100
        @goal.user.transactions.income.sum(:amount_cents) / subunit.to_f
      end
    end

    def habit_progress
      return @goal.current_value unless @goal.related.is_a?(Habit)
      @goal.related.habit_logs.where(completed: true).count
    end
  end
end
