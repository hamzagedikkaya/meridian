module Api
  module V1
    module Serialize
      module_function

      def subunit_to_unit(currency)
        CurrencyUnit.subunit_to_unit(currency)
      end

      def user(user)
        {
          id: user.id,
          name: user.display_name,
          display_name: user.display_name,
          initials: user.initials,
          email: user.email,
          currency: user.currency,
          subunit_to_unit: subunit_to_unit(user.currency),
          locale: user.locale,
          timezone: user.timezone,
          # The zone the server computes "today" in for this user, as an IANA
          # id and the offset in effect right now.
          timezone_iana: user.time_zone.tzinfo.identifier,
          utc_offset: user.time_zone.now.formatted_offset,
          theme_preference: user.theme_preference,
          # 0 = Sunday … 6 = Saturday, as on the web's preferences page.
          weekly_review_day: user.weekly_review_day
        }
      end

      # One choice of the time zone picker (GET /me/options). `value` is the
      # Rails zone name that user.timezone stores; `name` is the web's label,
      # which carries the zone's standard offset; `utc_offset` is the offset
      # in effect now, daylight saving included.
      def time_zone(zone)
        {
          value: zone.name,
          name: zone.to_s,
          iana: zone.tzinfo.identifier,
          utc_offset: zone.now.formatted_offset
        }
      end

      def account_brief(account)
        {
          id: account.id,
          name: account.name,
          color: account.color,
          currency: account.currency,
          subunit_to_unit: subunit_to_unit(account.currency)
        }
      end

      def category(category)
        {
          id: category.id,
          name: category.name,
          kind: category.kind,
          color: category.color,
          parent_id: category.parent_id,
          position: category.position
        }
      end

      def transaction(transaction)
        {
          id: transaction.id,
          kind: transaction.kind,
          amount_cents: transaction.amount_cents,
          date: transaction.date,
          description: transaction.description,
          note: transaction.note,
          account: account_brief(transaction.account),
          category: transaction.finance_category && category(transaction.finance_category),
          related_account: transaction.related_account &&
            { id: transaction.related_account.id, name: transaction.related_account.name }
        }
      end

      # Amounts are in the account currency's minor units (subunit_to_unit).
      # balance_cents is computed by the caller, in bulk for lists.
      def account(account, balance_cents:)
        {
          id: account.id,
          name: account.name,
          account_type: account.account_type,
          currency: account.currency,
          subunit_to_unit: subunit_to_unit(account.currency),
          color: account.color,
          initial_balance_cents: account.initial_balance_cents,
          balance_cents: balance_cents,
          archived: account.archived?,
          archived_at: account.archived_at
        }
      end

      # A Finance::BudgetStatus: the budget plus its month-to-date spend, in
      # the user's currency. `color` is the one to draw (the budget's own, or
      # its category's); `custom_color` is the budget's own or null.
      def budget(status)
        budget = status.budget
        {
          id: budget.id,
          finance_category_id: budget.finance_category_id,
          category: { id: status.category.id, name: status.category.name, color: status.category.color },
          color: status.color,
          custom_color: budget.color.presence,
          limit_cents: status.limit_cents,
          spent_cents: status.spent_cents,
          remaining_cents: status.remaining_cents,
          over_by_cents: status.over_by_cents,
          percent_used: status.percent_used,
          bar_percent: status.bar_percent,
          pace_percent: status.pace_percent,
          projected_cents: status.projected_cents,
          state: status.state
        }
      end

      # Amounts are in the account currency's minor units.
      def subscription(subscription)
        {
          id: subscription.id,
          name: subscription.name,
          vendor: subscription.vendor,
          amount_cents: subscription.amount_cents,
          frequency: subscription.frequency,
          next_charge_on: subscription.next_charge_on,
          start_date: subscription.start_date,
          end_date: subscription.end_date,
          active: subscription.active,
          color: subscription.color,
          note: subscription.note,
          monthly_amount_cents: subscription.monthly_amount_cents,
          yearly_amount_cents: subscription.yearly_amount_cents,
          account: account_brief(subscription.account),
          category: subscription.finance_category && category(subscription.finance_category)
        }
      end

      def currency(currency)
        {
          code: currency.iso_code,
          name: I18n.t(currency.iso_code, scope: "api.currencies", default: currency.name),
          symbol: currency.symbol,
          symbol_first: currency.symbol_first?,
          subunit_to_unit: currency.subunit_to_unit,
          decimal_places: currency.decimal_places
        }
      end

      # progress_source says where current_value comes from (see
      # Goals::CalculateProgress#source); only "manual" goals take
      # update_progress.
      def goal(goal, related_details: true)
        days = goal.days_remaining
        {
          id: goal.id,
          name: goal.name,
          description: goal.description,
          target_type: goal.target_type,
          status: goal.status,
          color: goal.color,
          unit: goal.unit,
          deadline: goal.deadline,
          days_remaining: days,
          deadline_badge: deadline_badge(days),
          target_value: goal.target_value.to_f,
          current_value: goal.current_value.to_f,
          progress_percent: goal.progress_percent,
          progress_source: Goals::CalculateProgress.new(goal).source,
          related: related_details ? goal_related(goal) : nil
        }
      end

      def deadline_badge(days)
        return nil if days.nil?
        if days.negative?
          { state: "overdue", days: -days }
        elsif days.zero?
          { state: "today", days: 0 }
        elsif days <= 7
          { state: "soon", days: days }
        else
          { state: "far", days: days }
        end
      end

      def goal_related(goal)
        related = goal.related
        case related
        when Account
          {
            type: "Account",
            id: related.id,
            name: related.name,
            balance_cents: related.balance_cents,
            currency: related.currency,
            subunit_to_unit: subunit_to_unit(related.currency)
          }
        when Habit
          {
            type: "Habit",
            id: related.id,
            name: related.name,
            current_streak: related.current_streak,
            completed_days: related.habit_logs.where(completed: true).count
          }
        end
      end

      # due_date and due_time are due_at read in the user's zone; due_time is
      # null for a date-only due (stored as 23:59:59 that day, see
      # Todo.end_of_due_day).
      def todo(todo)
        {
          id: todo.id,
          title: todo.title,
          body: todo.body,
          status: todo.status,
          priority: todo.priority,
          due_at: todo.due_at,
          due_date: todo.due_date,
          due_time: todo.due_time,
          completed_at: todo.completed_at,
          overdue: todo.overdue?,
          position: todo.position,
          goal_id: todo.goal_id,
          todo_list: todo.todo_list &&
            { id: todo.todo_list.id, name: todo.todo_list.name, color: todo.todo_list.color },
          subtask_count: todo.subtasks.size
        }
      end

      # open_count: pending and in-progress todos in the list; todos_count:
      # every todo in it, whatever its status (what a delete would remove).
      def todo_list(list, open_count:, todos_count:)
        {
          id: list.id,
          name: list.name,
          color: list.color,
          position: list.position,
          archived: list.archived?,
          archived_at: list.archived_at,
          open_count: open_count,
          todos_count: todos_count
        }
      end

      # `recurring`: the row is a series expanded from recurrence_rule, and
      # start_at/end_at are its first occurrence. `full` adds what the edit
      # form needs.
      def event(event, occurrences: nil, full: false)
        json = {
          id: event.id,
          title: event.title,
          start_at: event.start_at,
          end_at: event.end_at,
          all_day: event.all_day,
          color: event.color,
          event_type: event.event_type,
          location: event.location,
          duration_minutes: event.duration_minutes,
          recurring: event.repeats?
        }
        if full
          json[:description] = event.description
          json[:recurrence_rule] = event.repeats? ? event.recurrence_rule : nil
        end
        json[:occurrences] = occurrences if occurrences
        json
      end

      # The list carries a 200-character body_plain preview. `full` (the
      # entry endpoints) carries the whole body: body_html to show, body_text
      # to edit, and body_format / body_formatting to tell whether editing it
      # as plain text keeps everything ("plain") or would drop formatting
      # added on the web ("rich"). There body_plain is the whole text too, so
      # older app versions, which fill their editor from it, no longer save a
      # cut-off body back.
      def journal_entry(entry, full: false)
        text = entry.body_text
        json = {
          id: entry.id,
          date: entry.date,
          title: entry.title,
          body_plain: full ? text : text.truncate(200),
          mood: entry.mood,
          mood_emoji: entry.mood_emoji,
          energy_level: entry.energy_level,
          weather: entry.weather,
          tags: entry.tag_list,
          has_gratitude: entry.gratitude.present?,
          created_at: entry.created_at
        }
        if full
          # ActionText::Content#to_s returns the stored HTML verbatim; the web
          # view sanitizes on render, the API used to skip that step. :body is
          # permitted as a raw string on create, so whatever was stored came
          # back out unchanged. An empty body is "", not the bare
          # <div class="trix-content"> wrapper the layout would render.
          json[:body_html] = if entry.body.body.blank?
            ""
          else
            ActionText::ContentHelper.sanitizer.sanitize(
              entry.body.to_s,
              tags: ActionText::ContentHelper.allowed_tags,
              attributes: ActionText::ContentHelper.allowed_attributes
            ).to_s
          end
          formatting = entry.body_formatting
          json[:body_text] = text
          json[:body_format] = formatting.empty? ? "plain" : "rich"
          json[:body_formatting] = formatting
          json[:gratitude] = entry.gratitude
          json[:updated_at] = entry.updated_at
        end
        json
      end

      # start_date: the first day PUT /habits/:id/logs/:date accepts (the
      # day the habit was created, in the user's zone).
      def habit(habit, streak:, chain:, today_log: nil)
        log = today_log || habit.log_for(Date.current)
        json = {
          id: habit.id,
          name: habit.name,
          description: habit.description,
          frequency: habit.frequency,
          target_count: habit.target_count,
          color: habit.color,
          goal_id: habit.goal_id,
          archived: habit.archived?,
          archived_at: habit.archived_at,
          created_at: habit.created_at,
          start_date: habit.start_date,
          current_streak: streak,
          longest_streak: habit.longest_streak,
          completion_rate_30d: habit.completion_rate(days: 30),
          today: { date: Date.current, completed: log.completed?, count: log.count },
          chain: chain
        }
        if habit.frequency != "daily"
          range = habit.period_range(Date.current)
          json[:period] = {
            range_start: range.begin,
            range_end: range.end,
            completed_count: habit.period_completed_count,
            complete: habit.period_complete?
          }
        end
        json
      end
    end
  end
end
