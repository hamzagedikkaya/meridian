class CreateEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :events do |t|
      t.references :user, null: false, foreign_key: true
      t.string  :title, null: false
      t.text    :description
      t.datetime :start_at, null: false
      t.datetime :end_at
      t.boolean :all_day, null: false, default: false
      t.string  :timezone
      t.string  :color, default: "#B8860B"
      t.string  :location
      t.string  :event_type, null: false, default: "personal" # personal | work | health | finance | other
      t.boolean :recurring, null: false, default: false
      t.text    :recurrence_rule
      t.references :related, polymorphic: true

      t.timestamps
    end

    add_index :events, [ :user_id, :start_at ]
  end
end
