class Event < ApplicationRecord
  EVENT_TYPES = %w[personal work health finance other].freeze

  belongs_to :user
  belongs_to :related, polymorphic: true, optional: true

  before_validation :normalize_recurrence_rule

  validates :title, presence: true, length: { maximum: 200 }
  validates :start_at, presence: true
  validates :event_type, inclusion: { in: EVENT_TYPES }
  validate  :end_at_after_start_at
  # Checked when the rule or the start changes, so an older row stays
  # editable; a rule that no longer expands falls back to a one-off in
  # #occurrences_between.
  validate  :recurrence_rule_supported, if: -> {
    recurrence_rule.present? && (will_save_change_to_recurrence_rule? || will_save_change_to_start_at?)
  }

  scope :for_month, ->(year, month) {
    start_of_month = Date.new(year, month, 1)
    end_of_month   = start_of_month.end_of_month
    where(start_at: start_of_month.beginning_of_day..end_of_month.end_of_day)
  }
  scope :for_day, ->(date) { where(start_at: date.all_day) }
  scope :upcoming, -> { where("start_at >= ?", Time.current).order(:start_at) }
  scope :recurring, -> { where(recurring: true) }

  # Every event of +scope+ that occurs on at least one day from +from+ to
  # +to+ (whole days in the request's zone), paired with those days: one-offs
  # that start in the window, and series anchored before it, expanded from
  # their rule. The one reading the web calendar, the dashboard and the API
  # share, so they agree about the same rows.
  def self.occurrences_by_event(scope, from, to)
    window = from.beginning_of_day..to.end_of_day
    scope.where(start_at: window).or(scope.recurring.where(start_at: ...window.begin)).filter_map do |event|
      dates = event.occurrences_between(from, to).select { |date| date.between?(from, to) }
      [ event, dates ] if dates.any?
    end
  end

  def duration_minutes
    return nil unless end_at
    ((end_at - start_at) / 60).to_i
  end

  # One row stands for the whole series: its occurrences are expanded from
  # the rule at read time, so an edit or a delete applies to all of them.
  def repeats?
    recurring? && recurrence_rule.present?
  end

  # Materialize concrete occurrences in a date range for recurring events.
  # Dates are whole days in Time.zone (the request's user zone): `from` starts
  # at its midnight and `to` runs to its end. Date#to_time would use the server
  # process zone and stop at the *start* of `to`, dropping that day.
  #
  # Only a rule RecurrenceRule accepts is expanded (at most one occurrence a
  # day); anything else, such as a MINUTELY rule stored before rules were
  # validated, counts as a one-off on its start date.
  def occurrences_between(from, to)
    rule = RecurrenceRule.new(recurrence_rule) if repeats?
    return [ start_at.to_date ] unless rule&.valid?

    range_start = from.acts_like?(:time) ? from : from.beginning_of_day
    range_end = to.acts_like?(:time) ? to : to.end_of_day
    schedule = IceCube::Schedule.new(start_at)
    schedule.add_recurrence_rule(rule.to_ice_cube)
    schedule.occurrences_between(range_start, range_end).map(&:to_date)
  rescue StandardError
    [ start_at.to_date ]
  end

  private

  def end_at_after_start_at
    return unless end_at.present? && start_at.present?
    errors.add(:end_at, :must_be_after_start) if end_at <= start_at
  end

  # A changed rule is stored in RecurrenceRule's normal form (upper case, no
  # "RRULE:" prefix, UNTIL as a UTC instant read in the user's zone), and
  # `recurring` follows it: an event repeats exactly when it has a rule.
  def normalize_recurrence_rule
    return unless will_save_change_to_recurrence_rule?

    self.recurrence_rule = RecurrenceRule.normalize(recurrence_rule)
    self.recurring = recurrence_rule.present?
  end

  def recurrence_rule_supported
    rule = RecurrenceRule.new(recurrence_rule)
    problem = rule.problems.first if will_save_change_to_recurrence_rule?
    if problem
      errors.add(:recurrence_rule, problem.type, **problem.options)
    elsif rule.valid? && start_at.present? && !rule.occurs_from?(start_at)
      errors.add(:recurrence_rule, :no_occurrences)
    end
  end
end
