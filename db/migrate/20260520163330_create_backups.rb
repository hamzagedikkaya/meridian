class CreateBackups < ActiveRecord::Migration[8.0]
  def change
    create_table :backups do |t|
      t.references :user, null: false, foreign_key: true
      t.string  :filename
      t.string  :status, null: false, default: "pending" # pending | running | succeeded | failed
      t.bigint  :size_bytes
      t.text    :note
      t.string  :meridian_version
      t.string  :schema_version
      t.text    :error_message

      t.timestamps
    end

    add_index :backups, [ :user_id, :created_at ]
  end
end
