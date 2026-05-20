class Backup < ApplicationRecord
  STATUSES = %w[pending running succeeded failed].freeze
  MERIDIAN_VERSION = "1.0.0"

  belongs_to :user
  has_one_attached :archive

  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }
  scope :succeeded, -> { where(status: "succeeded") }

  def succeeded?
    status == "succeeded"
  end

  def display_size
    return "—" unless size_bytes
    units = %w[B KB MB GB]
    val = size_bytes.to_f
    i = 0
    while val >= 1024 && i < units.size - 1
      val /= 1024
      i += 1
    end
    "#{val.round(1)} #{units[i]}"
  end
end
