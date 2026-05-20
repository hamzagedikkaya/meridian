class CreateTodoLists < ActiveRecord::Migration[8.0]
  def change
    create_table :todo_lists do |t|
      t.references :user, null: false, foreign_key: true
      t.string  :name, null: false
      t.string  :color, default: "#B8860B"
      t.string  :icon
      t.integer :position, null: false, default: 0
      t.datetime :archived_at

      t.timestamps
    end

    add_index :todo_lists, [ :user_id, :position ]
  end
end
