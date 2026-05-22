class SearchController < ApplicationController
  def index
    q = params[:q].to_s.strip
    if q.blank?
      render json: { results: [] } and return
    end

    pattern = "%#{q}%"
    results = []

    current_user.transactions.includes(:account).where("description ILIKE ?", pattern).limit(5).each do |t|
      fallback_title = t.description.presence || I18n.t("enums.transaction_kind.#{t.kind}")
      results << { type: I18n.t("global_search.types.Transaction"), id: t.id, title: fallback_title, subtitle: "#{t.date} · #{t.account.name}", url: finance_transaction_path(t) }
    end

    current_user.todos.where("title ILIKE ? OR body ILIKE ?", pattern, pattern).limit(5).each do |t|
      results << { type: I18n.t("global_search.types.Todo"), id: t.id, title: t.title, subtitle: I18n.t("enums.todo_status.#{t.status}"), url: edit_todo_path(t) }
    end

    current_user.journal_entries.where("title ILIKE ? OR tags ILIKE ?", pattern, pattern).limit(5).each do |e|
      results << { type: I18n.t("global_search.types.Journal"), id: e.id, title: e.title.presence || I18n.t("global_search.journal_default"), subtitle: e.date.to_s, url: journal_entry_path(e) }
    end

    current_user.events.where("title ILIKE ? OR location ILIKE ? OR description ILIKE ?", pattern, pattern, pattern).limit(5).each do |e|
      results << { type: I18n.t("global_search.types.Event"), id: e.id, title: e.title, subtitle: I18n.l(e.start_at, format: "%d %b %Y"), url: event_path(e) }
    end

    current_user.goals.where("name ILIKE ? OR description ILIKE ?", pattern, pattern).limit(5).each do |g|
      results << { type: I18n.t("global_search.types.Goal"), id: g.id, title: g.name, subtitle: I18n.t("global_search.goal_progress", percent: g.progress_percent), url: goal_path(g) }
    end

    matching_habits = current_user.habits.where("name ILIKE ? OR description ILIKE ?", pattern, pattern).limit(5).to_a
    habit_streaks = Habit.streaks_for(matching_habits)
    matching_habits.each do |h|
      results << { type: I18n.t("global_search.types.Habit"), id: h.id, title: h.name, subtitle: I18n.t("global_search.habit_streak", days: habit_streaks[h.id]), url: habit_path(h) }
    end

    current_user.subscriptions.where("name ILIKE ? OR vendor ILIKE ?", pattern, pattern).limit(5).each do |s|
      results << { type: I18n.t("global_search.types.Subscription"), id: s.id, title: s.name, subtitle: "#{I18n.t("enums.frequency.#{s.frequency}")} · #{s.amount_cents / 100} #{s.account_currency}", url: finance_subscription_path(s) }
    end

    render json: { results: results }
  end
end
