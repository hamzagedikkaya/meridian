class FocusSession < ApplicationRecord
  MODES = %w[focus short_break long_break].freeze

  belongs_to :user
  belongs_to :todo, optional: true

  validates :mode, inclusion: { in: MODES }
  validates :duration_seconds, numericality: { greater_than: 0 }
  validates :started_at, presence: true

  scope :today, -> { where(started_at: Date.current.all_day) }
  scope :focus_only, -> { where(mode: "focus") }
  scope :completed, -> { where.not(completed_at: nil) }
end
