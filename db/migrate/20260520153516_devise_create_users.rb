# frozen_string_literal: true

class DeviseCreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      ## Devise: Database authenticatable
      t.string :email,              null: false, default: ""
      t.string :encrypted_password, null: false, default: ""

      ## Devise: Recoverable
      t.string   :reset_password_token
      t.datetime :reset_password_sent_at

      ## Devise: Rememberable
      t.datetime :remember_created_at

      ## Meridian profile fields
      t.string  :name
      t.string  :timezone,           null: false, default: "Istanbul"
      t.string  :currency,           null: false, default: "TRY"
      t.string  :locale,             null: false, default: "tr"
      t.string  :theme_preference,   null: false, default: "system"  # dark | light | system
      t.integer :weekly_review_day,  null: false, default: 0          # 0 = Sunday

      t.timestamps null: false
    end

    add_index :users, :email, unique: true
    add_index :users, :reset_password_token, unique: true
  end
end
