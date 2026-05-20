class CreateJournalEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :journal_entries do |t|
      t.references :user, null: false, foreign_key: true
      t.date    :date, null: false
      t.string  :title
      t.string  :mood
      t.string  :weather
      t.integer :energy_level
      t.text    :gratitude
      t.string  :tags  # comma-separated

      t.timestamps
    end

    add_index :journal_entries, [ :user_id, :date ]
  end
end
