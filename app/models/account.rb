class Account < ApplicationRecord
  ACCOUNT_TYPES = %w[cash bank credit_card savings crypto].freeze

  belongs_to :user
  has_many :transactions, dependent: :destroy
  has_many :outgoing_transfers, class_name: "Transaction", foreign_key: :related_account_id, dependent: :nullify, inverse_of: :related_account
  has_many :subscriptions, dependent: :destroy

  monetize :initial_balance_cents, with_model_currency: :currency

  validates :name, presence: true, length: { maximum: 60 }
  validates :account_type, inclusion: { in: ACCOUNT_TYPES }
  validates :currency, presence: true, length: { is: 3 }

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  def archived?
    archived_at.present?
  end

  def balance_cents
    incomes  = transactions.where(kind: "income").sum(:amount_cents)
    expenses = transactions.where(kind: "expense").sum(:amount_cents)
    transfers_out = transactions.where(kind: "transfer").sum(:amount_cents)
    transfers_in  = Transaction.where(related_account_id: id, kind: "transfer").sum(:amount_cents)
    initial_balance_cents + incomes - expenses - transfers_out + transfers_in
  end

  def balance
    Money.new(balance_cents, currency)
  end
end
