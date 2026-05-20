class CreateAccounts < ActiveRecord::Migration[8.0]
  def change
    create_table :accounts do |t|
      t.references :user, null: false, foreign_key: true
      t.string  :name, null: false
      t.string  :account_type, null: false, default: "cash"
      t.string  :currency, null: false, default: "TRY"
      t.integer :initial_balance_cents, null: false, default: 0
      t.string  :color, default: "#B8860B"
      t.string  :icon
      t.datetime :archived_at

      t.timestamps
    end

    add_index :accounts, [ :user_id, :archived_at ]
  end
end
