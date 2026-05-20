class CreateHabitLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :habit_logs do |t|
      t.references :habit, null: false, foreign_key: true
      t.date    :date, null: false
      t.boolean :completed, null: false, default: false
      t.integer :count, null: false, default: 0
      t.text    :note

      t.timestamps
    end

    add_index :habit_logs, [ :habit_id, :date ], unique: true
  end
end
