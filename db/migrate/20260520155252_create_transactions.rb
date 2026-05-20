class CreateTransactions < ActiveRecord::Migration[8.0]
  def change
    create_table :transactions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.references :finance_category, foreign_key: true
      t.references :related_account, foreign_key: { to_table: :accounts }
      t.integer :amount_cents, null: false, default: 0
      t.string  :kind, null: false  # income | expense | transfer
      t.string  :description
      t.text    :note
      t.date    :date, null: false
      t.datetime :occurred_at
      t.boolean :recurring, null: false, default: false
      t.text    :recurrence_rule
      t.references :parent_transaction, foreign_key: { to_table: :transactions }

      t.timestamps
    end

    add_index :transactions, [ :user_id, :date ]
    add_index :transactions, [ :user_id, :kind, :date ]
    add_index :transactions, [ :account_id, :date ]
  end
end
