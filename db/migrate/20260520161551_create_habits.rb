class CreateHabits < ActiveRecord::Migration[8.0]
  def change
    create_table :habits do |t|
      t.references :user, null: false, foreign_key: true
      t.string  :name, null: false
      t.text    :description
      t.string  :frequency, null: false, default: "daily"  # daily | weekly | monthly
      t.integer :target_count, null: false, default: 1
      t.string  :color, default: "#B8860B"
      t.string  :icon
      t.datetime :archived_at

      t.timestamps
    end

    add_index :habits, [ :user_id, :archived_at ]
  end
end
