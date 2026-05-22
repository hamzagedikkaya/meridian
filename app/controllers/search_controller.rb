class SearchController < ApplicationController
  def index
    q = params[:q].to_s.strip
    if q.blank?
      render json: { results: [] } and return
    end

    pattern = "%#{q}%"
    results = []

    current_user.transactions.includes(:account).where("description ILIKE ? OR note ILIKE ?", pattern, pattern).limit(5).each do |t|
      results << { type: "Transaction", id: t.id, title: t.description.presence || t.kind.titleize, subtitle: "#{t.date} · #{t.account.name}", url: finance_transaction_path(t) }
    end

    current_user.todos.where("title ILIKE ? OR body ILIKE ?", pattern, pattern).limit(5).each do |t|
      results << { type: "Todo", id: t.id, title: t.title, subtitle: t.status.titleize, url: edit_todo_path(t) }
    end

    current_user.journal_entries.where("title ILIKE ? OR tags ILIKE ?", pattern, pattern).limit(5).each do |e|
      results << { type: "Journal", id: e.id, title: e.title.presence || "Entry", subtitle: e.date.to_s, url: journal_entry_path(e) }
    end

    current_user.events.where("title ILIKE ? OR location ILIKE ? OR description ILIKE ?", pattern, pattern, pattern).limit(5).each do |e|
      results << { type: "Event", id: e.id, title: e.title, subtitle: e.start_at.strftime("%d %b %Y"), url: event_path(e) }
    end

    current_user.goals.where("name ILIKE ? OR description ILIKE ?", pattern, pattern).limit(5).each do |g|
      results << { type: "Goal", id: g.id, title: g.name, subtitle: "#{g.progress_percent}% complete", url: goal_path(g) }
    end

    matching_habits = current_user.habits.where("name ILIKE ? OR description ILIKE ?", pattern, pattern).limit(5).to_a
    habit_streaks = Habit.streaks_for(matching_habits)
    matching_habits.each do |h|
      results << { type: "Habit", id: h.id, title: h.name, subtitle: "🔥 #{habit_streaks[h.id]}d streak", url: habit_path(h) }
    end

    current_user.subscriptions.where("name ILIKE ? OR vendor ILIKE ?", pattern, pattern).limit(5).each do |s|
      results << { type: "Subscription", id: s.id, title: s.name, subtitle: "#{s.frequency.titleize} · #{s.amount_cents / 100} #{s.account_currency}", url: finance_subscription_path(s) }
    end

    render json: { results: results }
  end
end
