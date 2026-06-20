class CreateBudgets < ActiveRecord::Migration[8.1]
  def change
    create_table :budgets do |t|
      t.references :user, null: false, foreign_key: true
      t.references :finance_category, null: false, foreign_key: true
      t.integer :monthly_limit_cents, null: false, default: 0
      t.string :period, null: false, default: "monthly"
      t.string :color
      t.timestamps
    end

    add_index :budgets, [ :user_id, :finance_category_id ], unique: true
  end
end
