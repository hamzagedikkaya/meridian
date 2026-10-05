class User < ApplicationRecord
  # No :registerable — Meridian is a single-household app served on a LAN, so an
  # open POST /users would let anyone on the network mint an account.
  devise :database_authenticatable,
         :recoverable, :rememberable, :validatable

  has_secure_token :api_token
  # A new password replaces the API token, whatever changed it (PATCH
  # /me/password, the web profile page, a Devise reset link), so changing the
  # password after a phone is lost or a token leaks signs that copy out.
  before_update :replace_api_token, if: :will_save_change_to_encrypted_password?

  has_one_attached :avatar

  AVATAR_CONTENT_TYPES = %w[image/png image/jpeg image/webp image/gif].freeze
  AVATAR_MAX_BYTES = 5.megabytes

  validate :avatar_is_a_bounded_image

  has_many :accounts, dependent: :destroy
  has_many :finance_categories, dependent: :destroy
  has_many :transactions, dependent: :destroy
  has_many :budgets, dependent: :destroy
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
  has_many :weekly_reviews, dependent: :destroy
  has_many :focus_sessions, dependent: :destroy

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

  # The zone this user's requests run in, so "today" and naive datetimes mean
  # the user's wall clock rather than UTC. A blank or unknown stored name
  # (validation only runs on save) falls back to the app default instead of
  # raising mid-request.
  def time_zone
    ActiveSupport::TimeZone[timezone.to_s] || Time.zone_default
  end

  # The locale this user's requests run in; unsupported values fall back to
  # the app default for the same reason as #time_zone.
  def preferred_locale
    I18n.locale_available?(locale) ? locale.to_sym : I18n.default_locale
  end

  def initials
    return "?" if display_name.blank?
    display_name.split(/\s+/).first(2).map { |part| part[0]&.upcase }.join
  end

  # Replaces the API token. There is one token per user, so every device
  # using the old one is signed out. Written without validations (unlike
  # regenerate_api_token) so that signing out cannot fail because of an
  # unrelated invalid attribute, e.g. a legacy row saved before a newer rule.
  def rotate_api_token!
    update_column(:api_token, self.class.generate_unique_secure_token)
  end

  # Returns the 30-day "perfect day" chain — a day is perfect when every habit
  # that was active on that day was completed. See PerfectDayChain for shape.
  def perfect_day_chain(days: 30, end_date: Date.current)
    PerfectDayChain.new(self, days: days, end_date: end_date).to_a
  end

  private

  def replace_api_token
    self.api_token = self.class.generate_unique_secure_token
  end

  # The uploaded bytes are handed to ImageMagick for variant processing, and
  # `accept: "image/*"` in the form is client-side only.
  def avatar_is_a_bounded_image
    return unless avatar.attached?

    unless AVATAR_CONTENT_TYPES.include?(avatar.blob.content_type)
      errors.add(:avatar, :invalid_content_type)
    end
    errors.add(:avatar, :too_large) if avatar.blob.byte_size.to_i > AVATAR_MAX_BYTES
  end
end
