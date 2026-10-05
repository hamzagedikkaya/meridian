class Subscription < ApplicationRecord
  FREQUENCIES = %w[weekly monthly yearly].freeze

  belongs_to :user
  belongs_to :goal, optional: true
  belongs_to :account
  belongs_to :finance_category, optional: true

  monetize :amount_cents, with_model_currency: :account_currency

  belongs_to_same_user :account, :finance_category, :goal
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

  # This subscription's share of the subscriptions page's "monthly average":
  # the amount itself when monthly, otherwise a twelfth of the yearly amount,
  # rounded down (Finance::SubscriptionsController#index).
  def monthly_amount_cents
    frequency == "monthly" ? amount_cents : yearly_amount_cents.to_i / 12
  end

  def yearly_amount
    Money.new(yearly_amount_cents, account_currency)
  end

  # Moves next_charge_on one period on. A monthly or yearly date that a
  # short month cut to its last day (31 January → 28 February) goes back to
  # the start date's day when the next month has it (→ 31 March), as the
  # dates counted from start_date do; chaining +1 month would keep the 28th
  # for good.
  def advance_next_charge!
    return unless next_charge_on
    self.next_charge_on = case frequency
    when "weekly"  then next_charge_on + 7.days
    when "monthly" then keep_billing_day(next_charge_on + 1.month)
    when "yearly"  then keep_billing_day(next_charge_on + 1.year)
    end
    save!
  end

  private

  def keep_billing_day(date)
    day = start_date&.day
    return date unless day && next_charge_on.day < day && next_charge_on == next_charge_on.end_of_month

    date.change(day: [ day, date.end_of_month.day ].min)
  end
end
