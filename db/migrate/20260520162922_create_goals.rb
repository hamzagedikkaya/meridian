class CreateGoals < ActiveRecord::Migration[8.0]
  def change
    create_table :goals do |t|
      t.references :user, null: false, foreign_key: true
      t.string  :name, null: false
      t.text    :description
      t.string  :target_type, null: false, default: "custom" # financial | habit | custom
      t.decimal :target_value, precision: 14, scale: 2, null: false, default: 0
      t.decimal :current_value, precision: 14, scale: 2, null: false, default: 0
      t.string  :unit, default: "TRY"
      t.date    :deadline
      t.string  :color, default: "#B8860B"
      t.string  :icon
      t.string  :status, null: false, default: "active" # active | achieved | abandoned
      t.integer :position, null: false, default: 0
      t.references :related, polymorphic: true

      t.timestamps
    end

    add_index :goals, [ :user_id, :status, :position ]
  end
end
