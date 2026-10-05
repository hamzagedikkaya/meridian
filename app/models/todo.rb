class Todo < ApplicationRecord
  PRIORITIES = %w[low medium high urgent].freeze
  STATUSES   = %w[pending in_progress done cancelled].freeze
  OPEN_STATUSES = %w[pending in_progress].freeze

  belongs_to :user
  belongs_to :goal, optional: true
  belongs_to :todo_list, optional: true
  belongs_to :parent, class_name: "Todo", optional: true
  has_many :subtasks, class_name: "Todo", foreign_key: :parent_id, dependent: :nullify
  # focus_sessions.todo_id has a foreign key: without this, deleting a todo
  # that was ever focused on (or a list holding one) raised InvalidForeignKey.
  # The sessions stay in the focus history, unlinked.
  has_many :focus_sessions, dependent: :nullify

  belongs_to_same_user :goal, :todo_list, :parent
  validates :title, presence: true, length: { maximum: 200 }
  validates :priority, inclusion: { in: PRIORITIES }
  validates :status, inclusion: { in: STATUSES }

  scope :pending,        -> { where(status: "pending") }
  scope :in_progress,    -> { where(status: "in_progress") }
  scope :done,           -> { where(status: "done") }
  scope :cancelled,      -> { where(status: "cancelled") }
  scope :open,           -> { where(status: OPEN_STATUSES) }
  scope :due_today,      -> { open.where(due_at: Date.current.all_day) }
  # A time range, Monday 00:00 to Sunday 23:59:59 in the request's zone. A
  # Date range here would compare due_at with UTC midnights and drop Sunday.
  scope :due_this_week,  -> { open.where(due_at: Time.current.all_week) }
  # The next +days+ days after today: tomorrow 00:00 to the end of today +
  # +days+, in the request's zone.
  scope :due_upcoming,   ->(days = 7) { open.where(due_at: Date.tomorrow.beginning_of_day..(Date.current + days).end_of_day) }
  scope :overdue,        -> { open.where("due_at < ?", Time.current) }
  scope :undated,        -> { open.where(due_at: nil) }
  scope :ordered,        -> { order(:position, :id) }

  before_save :sync_completed_at

  # A due date without a time of day is stored as 23:59:59 on that day in
  # the request's zone (the user's): due_today covers it all day and it only
  # becomes overdue (due_at < now) once the day is over. Midnight would make
  # it overdue, and counted as such, for that entire day.
  def self.end_of_due_day(date)
    date.in_time_zone.change(hour: 23, min: 59, sec: 59)
  end

  def done?
    status == "done"
  end

  def overdue?
    open? && due_at.present? && due_at < Time.current
  end

  def open?
    OPEN_STATUSES.include?(status)
  end

  # The due day in the request's zone.
  def due_date
    due_at&.to_date
  end

  # "HH:MM" in the request's zone; nil without a due date or when the due
  # date has no time (see .end_of_due_day).
  def due_time
    due_at.strftime("%H:%M") if due_at && !due_date_only?
  end

  def due_date_only?
    due_at.present? && due_at.hour == 23 && due_at.min == 59 && due_at.sec == 59
  end

  private

  def sync_completed_at
    if status_changed?
      self.completed_at = status == "done" ? Time.current : nil
    end
  end
end
