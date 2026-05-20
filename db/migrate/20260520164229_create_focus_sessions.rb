class CreateFocusSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :focus_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :todo, foreign_key: true
      t.integer  :duration_seconds, null: false, default: 1500  # 25 min default
      t.datetime :started_at, null: false
      t.datetime :completed_at
      t.string   :mode, null: false, default: "focus" # focus | short_break | long_break

      t.timestamps
    end

    add_index :focus_sessions, [ :user_id, :started_at ]
  end
end
