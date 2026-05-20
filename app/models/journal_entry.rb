class JournalEntry < ApplicationRecord
  MOODS = %w[great good neutral bad awful].freeze
  MOOD_EMOJI = { "great" => "😄", "good" => "🙂", "neutral" => "😐", "bad" => "🙁", "awful" => "😞" }.freeze

  belongs_to :user
  has_rich_text :body
  has_many_attached :attachments

  validates :date, presence: true
  validates :mood, inclusion: { in: MOODS }, allow_nil: true
  validates :energy_level, inclusion: { in: 1..5 }, allow_nil: true

  scope :recent, -> { order(date: :desc, created_at: :desc) }
  scope :by_month, ->(year, month) { where(date: Date.new(year, month, 1)..Date.new(year, month, 1).end_of_month) }

  def mood_emoji
    MOOD_EMOJI[mood]
  end

  def tag_list
    tags.to_s.split(",").map(&:strip).reject(&:blank?)
  end
end
