class Tag < ApplicationRecord
  belongs_to :user
  has_many :taggings, dependent: :destroy
  has_many :transactions, through: :taggings, source: :taggable, source_type: "Transaction"
  has_many :todos, through: :taggings, source: :taggable, source_type: "Todo"
  has_many :journal_entries, through: :taggings, source: :taggable, source_type: "JournalEntry"
  has_many :events, through: :taggings, source: :taggable, source_type: "Event"
  has_many :goals, through: :taggings, source: :taggable, source_type: "Goal"

  validates :name, presence: true, length: { maximum: 40 }
  validates :slug, presence: true, uniqueness: { scope: :user_id }

  before_validation :generate_slug

  scope :ordered, -> { order(:name) }

  private

  def generate_slug
    self.slug ||= name.to_s.parameterize
  end
end
