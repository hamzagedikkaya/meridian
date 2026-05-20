class Todo < ApplicationRecord
  PRIORITIES = %w[low medium high urgent].freeze
  STATUSES   = %w[pending in_progress done cancelled].freeze

  belongs_to :user
  belongs_to :todo_list, optional: true
  belongs_to :parent, class_name: "Todo", optional: true
  has_many :subtasks, class_name: "Todo", foreign_key: :parent_id, dependent: :nullify

  validates :title, presence: true, length: { maximum: 200 }
  validates :priority, inclusion: { in: PRIORITIES }
  validates :status, inclusion: { in: STATUSES }

  scope :pending,        -> { where(status: "pending") }
  scope :in_progress,    -> { where(status: "in_progress") }
  scope :done,           -> { where(status: "done") }
  scope :cancelled,      -> { where(status: "cancelled") }
  scope :open,           -> { where(status: %w[pending in_progress]) }
  scope :due_today,      -> { open.where(due_at: Date.current.all_day) }
  scope :due_this_week,  -> { open.where(due_at: Date.current.beginning_of_week..Date.current.end_of_week) }
  scope :overdue,        -> { open.where("due_at < ?", Time.current) }
  scope :ordered,        -> { order(:position, :id) }

  before_save :sync_completed_at

  def done?
    status == "done"
  end

  def overdue?
    open? && due_at.present? && due_at < Time.current
  end

  def open?
    %w[pending in_progress].include?(status)
  end

  private

  def sync_completed_at
    if status_changed?
      self.completed_at = status == "done" ? Time.current : nil
    end
  end
end
