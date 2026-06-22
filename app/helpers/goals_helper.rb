module GoalsHelper
  # A localized, color-coded deadline badge for a goal — replaces the raw
  # "30d" / "-5d" text. Overdue goals turn red, due-today/this-week amber, and
  # comfortably-distant deadlines stay muted. Returns nil when the goal has no
  # deadline so the caller can skip rendering.
  def goal_deadline_badge(goal)
    return nil unless goal.deadline

    days = goal.days_remaining
    if days.negative?
      { text: t("goals.deadline_overdue", count: -days), class: "text-[var(--color-expense)]" }
    elsif days.zero?
      { text: t("goals.deadline_today"), class: "text-[var(--color-warning)]" }
    elsif days <= 7
      { text: t("goals.deadline_remaining", count: days), class: "text-[var(--color-warning)]" }
    else
      { text: t("goals.deadline_remaining", count: days), class: "text-[var(--color-fg-muted)]" }
    end
  end
end
