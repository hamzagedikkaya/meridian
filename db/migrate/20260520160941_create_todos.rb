class CreateTodos < ActiveRecord::Migration[8.0]
  def change
    create_table :todos do |t|
      t.references :user, null: false, foreign_key: true
      t.references :todo_list, foreign_key: true
      t.string  :title, null: false
      t.text    :body
      t.datetime :due_at
      t.string  :priority, null: false, default: "medium"  # low | medium | high | urgent
      t.string  :status, null: false, default: "pending"   # pending | in_progress | done | cancelled
      t.integer :position, null: false, default: 0
      t.datetime :completed_at
      t.boolean :recurring, null: false, default: false
      t.text    :recurrence_rule
      t.references :parent, foreign_key: { to_table: :todos }

      t.timestamps
    end

    add_index :todos, [ :user_id, :status, :due_at ]
    add_index :todos, [ :todo_list_id, :position ]
  end
end
