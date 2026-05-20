class Subscription < ApplicationRecord
  FREQUENCIES = %w[weekly monthly yearly].freeze

  belongs_to :user
  belongs_to :goal, optional: true
  belongs_to :account
  belongs_to :finance_category, optional: true

  monetize :amount_cents, with_model_currency: :account_currency

  validates :name, presence: true, length: { maximum: 60 }
  validates :amount_cents, numericality: { greater_than: 0 }
  validates :frequency, inclusion: { in: FREQUENCIES }

  scope :active,    -> { where(active: true) }
  scope :inactive,  -> { where(active: false) }
  scope :upcoming,  -> { active.where(next_charge_on: ..Date.current + 30.days).order(:next_charge_on) }

  def account_currency
    account&.currency || "TRY"
  end

  def yearly_amount_cents
    case frequency
    when "weekly"  then amount_cents * 52
    when "monthly" then amount_cents * 12
    when "yearly"  then amount_cents
    end
  end

  def yearly_amount
    Money.new(yearly_amount_cents, account_currency)
  end

  def advance_next_charge!
    return unless next_charge_on
    self.next_charge_on = case frequency
    when "weekly"  then next_charge_on + 7.days
    when "monthly" then next_charge_on + 1.month
    when "yearly"  then next_charge_on + 1.year
    end
    save!
  end
end
