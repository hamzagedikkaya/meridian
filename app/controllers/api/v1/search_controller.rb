module Api
  module V1
    # GET /api/v1/search?q=
    #
    # The user's records whose text contains q, at most PER_TYPE of each
    # type, grouped in TYPES order: GlobalSearch's rows, which the web's
    # command palette (SearchController) lists too. Titles and subtitles are
    # ready to show, in the user's language and time zone.
    class SearchController < BaseController
      MIN_QUERY_LENGTH = 2
      MAX_QUERY_LENGTH = 100
      PER_TYPE = 5
      TYPES = %w[transaction todo event journal_entry goal habit subscription].freeze
      DATE_FORMAT = "%-d %b %Y".freeze
      TIME_FORMAT = "%-d %b %Y %H:%M".freeze

      def index
        query = search_query
        if query.length < MIN_QUERY_LENGTH
          return render_unprocessable(:query_too_short, field: :q,
            message: I18n.t("api.errors.query_too_short", count: MIN_QUERY_LENGTH), min_length: MIN_QUERY_LENGTH)
        end

        search = GlobalSearch.new(current_user, query, per_type: PER_TYPE)
        results = transaction_results(search) + todo_results(search) + event_results(search) +
                  journal_entry_results(search) + goal_results(search) + habit_results(search) +
                  subscription_results(search)
        render json: { query: query, results: results }
      end

      private

      # q stripped of surrounding spaces; absent counts as "". A list or an
      # object, or more than MAX_QUERY_LENGTH characters, is 422.
      def search_query
        value = params[:q]
        return "" if value.nil?
        raise InvalidParameter, :q unless value.is_a?(String)

        query = value.strip
        raise InvalidParameter, :q if query.length > MAX_QUERY_LENGTH

        query
      end

      def result(type, record, title, subtitle_parts)
        { type: type, id: record.id, title: title, subtitle: subtitle_parts.compact_blank.join(" · ") }
      end

      def transaction_results(search)
        search.transactions.map do |transaction|
          title = transaction.description.presence || I18n.t("enums.transaction_kind.#{transaction.kind}")
          accounts = transaction.account.name
          accounts += " → #{transaction.related_account.name}" if transaction.related_account
          result("transaction", transaction, title, [
            I18n.l(transaction.date, format: DATE_FORMAT), accounts,
            amount_text(transaction.amount_cents, transaction.account.currency, transaction.kind)
          ])
        end
      end

      def todo_results(search)
        search.todos.map do |todo|
          due = todo.due_date && I18n.t("api.search.due", date: I18n.l(todo.due_date, format: DATE_FORMAT))
          result("todo", todo, todo.title, [ I18n.t("enums.todo_status.#{todo.status}"), due ])
        end
      end

      def event_results(search)
        search.events.map do |event|
          start = event.all_day ? I18n.l(event.start_at.to_date, format: DATE_FORMAT) : I18n.l(event.start_at, format: TIME_FORMAT)
          result("event", event, event.title, [ start, event.location ])
        end
      end

      # An untitled entry is titled by the first line of its body.
      def journal_entry_results(search)
        search.journal_entries.map do |entry|
          title = entry.title.presence || entry.body_text.to_s.strip.lines.first.to_s.strip.truncate(80).presence ||
                  I18n.t("global_search.journal_default")
          result("journal_entry", entry, title, [ I18n.l(entry.date, format: DATE_FORMAT) ])
        end
      end

      def goal_results(search)
        search.goals.map do |goal|
          subtitle = if goal.status == "active"
            I18n.t("global_search.goal_progress", percent: goal.progress_percent.floor)
          else
            I18n.t("goals.statuses.#{goal.status}")
          end
          result("goal", goal, goal.name, [ subtitle ])
        end
      end

      # Archived habits say so. A streak shows only when there is one.
      def habit_results(search)
        habits = search.habits
        streaks = Habit.streaks_for(habits.reject(&:archived?))
        habits.map do |habit|
          streak = streaks[habit.id].to_i
          result("habit", habit, habit.name, [
            I18n.t("enums.frequency.#{habit.frequency}"),
            (I18n.t("api.search.habit_streak", count: streak) if streak.positive?),
            (I18n.t("api.search.archived") if habit.archived?)
          ])
        end
      end

      def subscription_results(search)
        search.subscriptions.map do |subscription|
          state = if !subscription.active
            I18n.t("api.search.inactive")
          elsif subscription.next_charge_on
            I18n.t("api.search.next_charge", date: I18n.l(subscription.next_charge_on, format: DATE_FORMAT))
          end
          result("subscription", subscription, subscription.name, [
            I18n.t("enums.frequency.#{subscription.frequency}"),
            amount_text(subscription.amount_cents, subscription.account.currency), state
          ])
        end
      end

      # "₺1.250,50" in Turkish, "₺1,250.50" in English, "12 gr" for gold;
      # "−" before an expense, "+" before an income.
      def amount_text(cents, currency, kind = nil)
        money_currency = Money::Currency.find(currency)
        subunit = money_currency&.subunit_to_unit || 100
        separator, delimiter = I18n.locale.to_s == "tr" ? [ ",", "." ] : [ ".", "," ]
        number = ActiveSupport::NumberHelper.number_to_rounded(
          BigDecimal(cents) / subunit,
          precision: Math.log10(subunit).round, separator: separator, delimiter: delimiter
        )
        symbol = money_currency&.symbol.presence || currency.to_s
        sign = { "expense" => "−", "income" => "+" }[kind]
        money_currency.nil? || money_currency.symbol_first? ? "#{sign}#{symbol}#{number}" : "#{sign}#{number} #{symbol}"
      end
    end
  end
end
