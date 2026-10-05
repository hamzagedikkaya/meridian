# The rows GET /api/v1/search and the web's command palette (SearchController)
# list for one query: the user's records of each type whose text contains it
# (TextMatching: any case, Turkish letters included; % and _ match
# themselves), in the same fields and the same order, at most +per_type+ of
# each. Each controller words its own titles and subtitles.
class GlobalSearch
  include TextMatching

  CLOSED_TODO_STATUSES = %w[done cancelled].freeze

  def initialize(user, query, per_type:)
    @user = user
    @query = query
    @per_type = per_type
  end

  # Description or note; newest first, as GET /transactions lists them.
  def transactions
    @user.transactions.includes(:account, :related_account)
         .where(matching(@query, ::Transaction, :description, :note))
         .recent.limit(@per_type).to_a
  end

  # Title or body; open todos first, then the most recently created.
  def todos
    @user.todos.where(matching(@query, Todo, :title, :body))
         .order(Arel.sql(closed_todos_last), created_at: :desc, id: :desc)
         .limit(@per_type).to_a
  end

  # Title, location or description; latest start first. A recurring event is
  # one row (its first occurrence).
  def events
    @user.events.where(matching(@query, Event, :title, :location, :description))
         .order(start_at: :desc, id: :desc).limit(@per_type).to_a
  end

  # Title, tags or the body's text; newest first.
  def journal_entries
    table = JournalEntry.arel_table
    @user.journal_entries.left_joins(:rich_text_body).with_rich_text_body
         .where(text_match([ table[:title], table[:tags], journal_body_text ], @query))
         .recent.limit(@per_type).to_a
  end

  # Name or description; active goals first, in their list order. Status and
  # progress are recomputed, as every goal read does (GET /goals), but only
  # in memory: search stays read-only.
  def goals
    goals = @user.goals.includes(:related).where(matching(@query, Goal, :name, :description))
                 .order(:position, :id).to_a
    goals.each do |goal|
      progress = Goals::CalculateProgress.new(goal)
      goal.current_value = progress.value
      goal.status = progress.status_for(goal.current_value)
    end
    goals.each_with_index.sort_by { |goal, index| [ goal.status == "active" ? 0 : 1, index ] }
         .first(@per_type).map(&:first)
  end

  # Name or description, archived habits included; active ones first, by name.
  def habits
    @user.habits.where(matching(@query, Habit, :name, :description))
         .order(Arel.sql("habits.archived_at IS NOT NULL"), :name, :id).limit(@per_type).to_a
  end

  # Name or vendor, inactive ones included; active first, soonest charge first.
  def subscriptions
    @user.subscriptions.includes(:account)
         .where(matching(@query, Subscription, :name, :vendor))
         .order(active: :desc, next_charge_on: :asc, id: :asc).limit(@per_type).to_a
  end

  private

  def closed_todos_last
    ActiveRecord::Base.sanitize_sql_array(
      [ "CASE WHEN todos.status IN (?) THEN 1 ELSE 0 END", CLOSED_TODO_STATUSES ]
    )
  end

  # A journal body is HTML; its tags are dropped before matching so a query
  # cannot match markup ("div", "br").
  def journal_body_text
    body = ActionText::RichText.arel_table[:body]
    Arel::Nodes::NamedFunction.new("regexp_replace", [
      Arel::Nodes::NamedFunction.new("COALESCE", [ body, Arel::Nodes.build_quoted("") ]),
      Arel::Nodes.build_quoted("<[^>]*>"), Arel::Nodes.build_quoted(" "), Arel::Nodes.build_quoted("g")
    ])
  end
end
