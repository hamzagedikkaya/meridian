class Budget < ApplicationRecord
  belongs_to :user
  belongs_to :finance_category

  monetize :monthly_limit_cents, with_model_currency: :budget_currency

  validates :monthly_limit_cents, numericality: { greater_than: 0 }
  validates :finance_category_id, uniqueness: { scope: :user_id }
  validate :category_is_expense_root

  scope :ordered, -> { joins(:finance_category).order("finance_categories.position", "finance_categories.name") }

  def budget_currency
    user&.currency.presence || "TRY"
  end

  private

  # Budgets sit at the same rollup level as the spending breakdown (root
  # expense categories), so subcategory spend can be summed against one cap.
  def category_is_expense_root
    return if finance_category.blank?

    errors.add(:finance_category_id, :must_be_expense) unless finance_category.kind == "expense"
    errors.add(:finance_category_id, :must_be_root) unless finance_category.parent_id.nil?
  end
end
