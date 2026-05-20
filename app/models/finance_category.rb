class FinanceCategory < ApplicationRecord
  KINDS = %w[income expense].freeze

  belongs_to :user
  belongs_to :parent, class_name: "FinanceCategory", optional: true
  has_many :children, class_name: "FinanceCategory", foreign_key: :parent_id, dependent: :destroy
  has_many :transactions, dependent: :nullify
  has_many :subscriptions, dependent: :nullify

  validates :name, presence: true, length: { maximum: 60 }
  validates :kind, inclusion: { in: KINDS }
  validates :name, uniqueness: { scope: [ :user_id, :parent_id ], case_sensitive: false }

  scope :income, -> { where(kind: "income") }
  scope :expense, -> { where(kind: "expense") }
  scope :roots, -> { where(parent_id: nil) }
  scope :ordered, -> { order(:position, :name) }
end
