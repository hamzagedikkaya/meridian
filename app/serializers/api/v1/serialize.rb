module Api
  module V1
    module Serialize
      module_function

      def subunit_to_unit(currency)
        Money::Currency.find(currency)&.subunit_to_unit || 100
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
          theme_preference: user.theme_preference
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

      def todo(todo)
        {
          id: todo.id,
          title: todo.title,
          body: todo.body,
          status: todo.status,
          priority: todo.priority,
          due_at: todo.due_at,
          overdue: todo.overdue?,
          position: todo.position,
          todo_list: todo.todo_list &&
            { id: todo.todo_list.id, name: todo.todo_list.name, color: todo.todo_list.color },
          subtask_count: todo.subtasks.size
        }
      end

      def event(event, occurrences: nil)
        json = {
          id: event.id,
          title: event.title,
          start_at: event.start_at,
          end_at: event.end_at,
          all_day: event.all_day,
          color: event.color,
          event_type: event.event_type,
          location: event.location,
          duration_minutes: event.duration_minutes
        }
        json[:occurrences] = occurrences if occurrences
        json
      end

      def journal_entry(entry, full: false)
        json = {
          id: entry.id,
          date: entry.date,
          title: entry.title,
          body_plain: entry.body&.to_plain_text.to_s.truncate(200),
          mood: entry.mood,
          mood_emoji: entry.mood_emoji,
          energy_level: entry.energy_level,
          weather: entry.weather,
          tags: entry.tag_list,
          has_gratitude: entry.gratitude.present?,
          created_at: entry.created_at
        }
        if full
          json[:body_html] = entry.body&.to_s.to_s
          json[:gratitude] = entry.gratitude
        end
        json
      end

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
