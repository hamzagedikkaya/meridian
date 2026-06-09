class RemoveIconColumns < ActiveRecord::Migration[8.1]
  TABLES = %i[accounts finance_categories goals habits subscriptions todo_lists].freeze

  def change
    TABLES.each { |t| remove_column t, :icon, :string }
  end
end
