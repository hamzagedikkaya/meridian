class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_one_attached :avatar

  has_many :accounts, dependent: :destroy
  has_many :finance_categories, dependent: :destroy
  has_many :transactions, dependent: :destroy
  has_many :subscriptions, dependent: :destroy
  has_many :todo_lists, dependent: :destroy
  has_many :todos, dependent: :destroy
  has_many :habits, dependent: :destroy
  has_many :habit_logs, through: :habits
  has_many :events, dependent: :destroy
  has_many :journal_entries, dependent: :destroy
  has_many :goals, dependent: :destroy
  has_many :backups, dependent: :destroy
  has_many :tags, dependent: :destroy

  THEME_PREFERENCES = %w[dark light system].freeze
  SUPPORTED_LOCALES = %w[tr en].freeze
  WEEKLY_REVIEW_DAYS = (0..6).to_a.freeze # 0 = Sunday, 6 = Saturday

  validates :name, presence: true, length: { maximum: 80 }
  validates :timezone, presence: true, inclusion: { in: ->(_) { ActiveSupport::TimeZone.all.map(&:name) } }
  validates :currency, presence: true, length: { is: 3 }
  validates :locale, inclusion: { in: SUPPORTED_LOCALES }
  validates :theme_preference, inclusion: { in: THEME_PREFERENCES }
  validates :weekly_review_day, inclusion: { in: WEEKLY_REVIEW_DAYS }

  def display_name
    name.presence || email.to_s.split("@").first
  end

  def initials
    return "?" if display_name.blank?
    display_name.split(/\s+/).first(2).map { |part| part[0]&.upcase }.join
  end
end
