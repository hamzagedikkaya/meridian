class Event < ApplicationRecord
  EVENT_TYPES = %w[personal work health finance other].freeze

  belongs_to :user
  belongs_to :related, polymorphic: true, optional: true

  validates :title, presence: true, length: { maximum: 200 }
  validates :start_at, presence: true
  validates :event_type, inclusion: { in: EVENT_TYPES }
  validate  :end_at_after_start_at

  scope :for_month, ->(year, month) {
    start_of_month = Date.new(year, month, 1)
    end_of_month   = start_of_month.end_of_month
    where(start_at: start_of_month.beginning_of_day..end_of_month.end_of_day)
  }
  scope :for_day, ->(date) { where(start_at: date.all_day) }
  scope :upcoming, -> { where("start_at >= ?", Time.current).order(:start_at) }
  scope :recurring, -> { where(recurring: true) }

  def duration_minutes
    return nil unless end_at
    ((end_at - start_at) / 60).to_i
  end

  # Materialize concrete occurrences in a date range for recurring events.
  def occurrences_between(from, to)
    return [ start_at.to_date ] unless recurring? && recurrence_rule.present?

    schedule = IceCube::Schedule.new(start_at)
    schedule.add_recurrence_rule(IceCube::Rule.from_ical(recurrence_rule))
    schedule.occurrences_between(from.to_time, to.to_time).map(&:to_date)
  rescue StandardError
    [ start_at.to_date ]
  end

  private

  def end_at_after_start_at
    return unless end_at.present? && start_at.present?
    errors.add(:end_at, "must be after start") if end_at <= start_at
  end
end
