class CreateFinanceCategories < ActiveRecord::Migration[8.0]
  def change
    create_table :finance_categories do |t|
      t.references :user, null: false, foreign_key: true
      t.string  :name, null: false
      t.string  :color, default: "#A09B8E"
      t.string  :icon
      t.string  :kind, null: false, default: "expense"  # income | expense
      t.references :parent, foreign_key: { to_table: :finance_categories }
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :finance_categories, [ :user_id, :kind ]
    add_index :finance_categories, [ :user_id, :position ]
  end
end
