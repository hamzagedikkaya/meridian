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

  # Consecutive-day journaling streak ending today (or yesterday if today
  # hasn't been journaled yet) — encourages the daily-writing habit. Counts
  # distinct entry dates, so multiple entries on one day still count as one.
  def self.current_streak_for(user, today = Date.current)
    dates = user.journal_entries.distinct.pluck(:date).compact.sort.reverse
    return 0 if dates.empty?

    cutoff = dates.include?(today) ? today : today - 1
    return 0 unless dates.first == cutoff

    streak = 1
    dates.each_cons(2) do |a, b|
      (a - b).to_i == 1 ? streak += 1 : break
    end
    streak
  end

  def mood_emoji
    MOOD_EMOJI[mood]
  end

  def tag_list
    tags.to_s.split(",").map(&:strip).reject(&:blank?)
  end
end
