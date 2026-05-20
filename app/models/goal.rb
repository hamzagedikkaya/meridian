class Goal < ApplicationRecord
  TARGET_TYPES = %w[financial habit custom].freeze
  STATUSES = %w[active achieved abandoned].freeze

  belongs_to :user
  belongs_to :related, polymorphic: true, optional: true

  has_many :habits, dependent: :nullify
  has_many :todos, dependent: :nullify
  has_many :subscriptions, dependent: :nullify

  validates :name, presence: true, length: { maximum: 100 }
  validates :target_type, inclusion: { in: TARGET_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :target_value, numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { where(status: "active") }
  scope :ordered, -> { order(:position, :id) }

  def progress_percent
    return 0 if target_value.to_f.zero?
    [ (current_value.to_f / target_value.to_f * 100).round(1), 100.0 ].min
  end

  def achieved?
    progress_percent >= 100.0
  end

  def days_remaining
    return nil unless deadline
    (deadline - Date.current).to_i
  end

  def recalculate_progress!
    Goals::CalculateProgress.call(self)
  end
end
