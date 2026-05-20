class CreateSubscriptions < ActiveRecord::Migration[8.0]
  def change
    create_table :subscriptions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.references :finance_category, foreign_key: true
      t.string  :name, null: false
      t.string  :vendor
      t.integer :amount_cents, null: false, default: 0
      t.string  :frequency, null: false, default: "monthly"  # weekly | monthly | yearly
      t.date    :next_charge_on
      t.date    :start_date
      t.date    :end_date
      t.boolean :active, null: false, default: true
      t.string  :color, default: "#B8860B"
      t.string  :icon
      t.text    :note

      t.timestamps
    end

    add_index :subscriptions, [ :user_id, :active, :next_charge_on ]
  end
end
