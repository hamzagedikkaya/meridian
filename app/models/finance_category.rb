class FinanceCategory < ApplicationRecord
  KINDS = %w[income expense].freeze

  belongs_to :user
  belongs_to :parent, class_name: "FinanceCategory", optional: true
  has_many :children, class_name: "FinanceCategory", foreign_key: :parent_id, dependent: :destroy
  has_many :transactions, dependent: :nullify
  has_many :subscriptions, dependent: :nullify
  has_many :budgets, dependent: :destroy

  validates :name, presence: true, length: { maximum: 60 }
  validates :kind, inclusion: { in: KINDS }
  validates :name, uniqueness: { scope: [ :user_id, :parent_id ], case_sensitive: false }
  validate :parent_constraints, if: :parent_id?
  validate :cannot_become_subcategory_with_children, if: -> { parent_id? && children.exists? }

  scope :income, -> { where(kind: "income") }
  scope :expense, -> { where(kind: "expense") }
  scope :roots, -> { where(parent_id: nil) }
  scope :ordered, -> { order(:position, :name) }

  def root?
    parent_id.nil?
  end

  private

  def parent_constraints
    if parent_id == id
      errors.add(:parent_id, :cannot_be_self)
    elsif parent.nil? || parent.user_id != user_id
      errors.add(:parent_id, :must_belong_to_same_user)
    elsif parent.kind != kind
      errors.add(:parent_id, :must_match_kind)
    elsif parent.parent_id.present?
      errors.add(:parent_id, :must_be_root)
    end
  end

  def cannot_become_subcategory_with_children
    errors.add(:parent_id, :cannot_have_children)
  end
end
