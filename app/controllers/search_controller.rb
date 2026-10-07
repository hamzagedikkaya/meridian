class SearchController < ApplicationController
  PER_TYPE = 5

  # The command palette's rows: GlobalSearch's, as GET /api/v1/search lists
  # them (the same fields, matching and order), worded for the web.
  def index
    q = params[:q].is_a?(String) ? params[:q].strip : ""
    if q.blank?
      render json: { results: [] } and return
    end

    search = GlobalSearch.new(current_user, q, per_type: PER_TYPE)
    results = []

    search.transactions.each do |t|
      fallback_title = t.description.presence || I18n.t("enums.transaction_kind.#{t.kind}")
      results << { type: I18n.t("global_search.types.Transaction"), id: t.id, title: fallback_title, subtitle: "#{t.date} · #{t.account.name}", url: finance_transaction_path(t) }
    end

    search.todos.each do |t|
      results << { type: I18n.t("global_search.types.Todo"), id: t.id, title: t.title, subtitle: I18n.t("enums.todo_status.#{t.status}"), url: edit_todo_path(t) }
    end

    search.events.each do |e|
      results << { type: I18n.t("global_search.types.Event"), id: e.id, title: e.title, subtitle: I18n.l(e.start_at, format: "%d %b %Y"), url: event_path(e) }
    end

    search.journal_entries.each do |e|
      results << { type: I18n.t("global_search.types.Journal"), id: e.id, title: e.title.presence || I18n.t("global_search.journal_default"), subtitle: e.date.to_s, url: journal_entry_path(e) }
    end

    search.goals.each do |g|
      results << { type: I18n.t("global_search.types.Goal"), id: g.id, title: g.name, subtitle: I18n.t("global_search.goal_progress", percent: g.progress_percent), url: goal_path(g) }
    end

    matching_habits = search.habits
    habit_streaks = Habit.streaks_for(matching_habits)
    matching_habits.each do |h|
      results << { type: I18n.t("global_search.types.Habit"), id: h.id, title: h.name, subtitle: I18n.t("global_search.habit_streak", days: habit_streaks[h.id]), url: habit_path(h) }
    end

    # The amount in its currency's own minor units (GAU has 1 per gram).
    search.subscriptions.each do |s|
      amount = helpers.money_format(s.amount_cents, currency: s.account_currency)
      results << { type: I18n.t("global_search.types.Subscription"), id: s.id, title: s.name, subtitle: "#{I18n.t("enums.frequency.#{s.frequency}")} · #{amount}", url: finance_subscription_path(s) }
    end

    render json: { results: results }
  end
end
