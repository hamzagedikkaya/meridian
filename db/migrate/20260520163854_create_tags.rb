class CreateTags < ActiveRecord::Migration[8.0]
  def change
    create_table :tags do |t|
      t.references :user, null: false, foreign_key: true
      t.string  :name, null: false
      t.string  :slug, null: false
      t.string  :color, default: "#A09B8E"

      t.timestamps
    end

    add_index :tags, [ :user_id, :slug ], unique: true
  end
end
