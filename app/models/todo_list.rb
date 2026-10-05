class TodoList < ApplicationRecord
  belongs_to :user
  has_many :todos, dependent: :destroy

  validates :name, presence: true, length: { maximum: 60 }

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :ordered, -> { order(:position, :name) }

  def archived?
    archived_at.present?
  end
end
