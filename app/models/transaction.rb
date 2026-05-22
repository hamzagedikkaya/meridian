class Transaction < ApplicationRecord
  KINDS = %w[income expense transfer].freeze

  belongs_to :user
  belongs_to :account
  belongs_to :finance_category, optional: true
  belongs_to :related_account, class_name: "Account", optional: true
  belongs_to :parent_transaction, class_name: "Transaction", optional: true
  has_many :child_transactions, class_name: "Transaction", foreign_key: :parent_transaction_id, dependent: :destroy

  monetize :amount_cents, with_model_currency: :account_currency

  validates :amount_cents, numericality: { greater_than: 0 }
  validates :kind, inclusion: { in: KINDS }
  validates :date, presence: true
  validate  :transfer_requires_related_account
  validate  :category_kind_matches_transaction_kind

  scope :this_month,    -> { where(date: Date.current.beginning_of_month..Date.current.end_of_month) }
  scope :this_year,     -> { where(date: Date.current.beginning_of_year..Date.current.end_of_year) }
  scope :income,        -> { where(kind: "income") }
  scope :expense,       -> { where(kind: "expense") }
  scope :transfer,      -> { where(kind: "transfer") }
  scope :between,       ->(from, to) { where(date: from..to) }
  scope :recent,        -> { order(date: :desc, created_at: :desc) }

  def account_currency
    account&.currency || "TRY"
  end

  private

  def transfer_requires_related_account
    return unless kind == "transfer" && related_account_id.blank?
    errors.add(:related_account_id, "must be present for transfers")
  end

  def category_kind_matches_transaction_kind
    return if finance_category.blank? || kind == "transfer"
    return if finance_category.kind == kind
    errors.add(:finance_category, "kind must match the transaction kind")
  end
end
