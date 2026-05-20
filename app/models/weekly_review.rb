class WeeklyReview < ApplicationRecord
  belongs_to :user

  validates :week_starting, presence: true, uniqueness: { scope: :user_id }

  scope :recent, -> { order(week_starting: :desc) }
  scope :completed, -> { where.not(completed_at: nil) }

  def completed?
    completed_at.present?
  end

  def week_end
    week_starting + 6.days
  end
end
