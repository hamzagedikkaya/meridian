# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_06_20_204024) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "accounts", force: :cascade do |t|
    t.string "account_type", default: "cash", null: false
    t.datetime "archived_at"
    t.string "color", default: "#B8860B"
    t.datetime "created_at", null: false
    t.string "currency", default: "TRY", null: false
    t.integer "initial_balance_cents", default: 0, null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "archived_at"], name: "index_accounts_on_user_id_and_archived_at"
    t.index ["user_id"], name: "index_accounts_on_user_id"
  end

  create_table "action_text_rich_texts", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "backups", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "filename"
    t.string "meridian_version"
    t.text "note"
    t.string "schema_version"
    t.bigint "size_bytes"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "created_at"], name: "index_backups_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_backups_on_user_id"
  end

  create_table "budgets", force: :cascade do |t|
    t.string "color"
    t.datetime "created_at", null: false
    t.bigint "finance_category_id", null: false
    t.integer "monthly_limit_cents", default: 0, null: false
    t.string "period", default: "monthly", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["finance_category_id"], name: "index_budgets_on_finance_category_id"
    t.index ["user_id", "finance_category_id"], name: "index_budgets_on_user_id_and_finance_category_id", unique: true
    t.index ["user_id"], name: "index_budgets_on_user_id"
  end

  create_table "events", force: :cascade do |t|
    t.boolean "all_day", default: false, null: false
    t.string "color", default: "#B8860B"
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "end_at"
    t.string "event_type", default: "personal", null: false
    t.string "location"
    t.text "recurrence_rule"
    t.boolean "recurring", default: false, null: false
    t.bigint "related_id"
    t.string "related_type"
    t.datetime "start_at", null: false
    t.string "timezone"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["related_type", "related_id"], name: "index_events_on_related"
    t.index ["user_id", "start_at"], name: "index_events_on_user_id_and_start_at"
    t.index ["user_id"], name: "index_events_on_user_id"
  end

  create_table "finance_categories", force: :cascade do |t|
    t.string "color", default: "#A09B8E"
    t.datetime "created_at", null: false
    t.string "kind", default: "expense", null: false
    t.string "name", null: false
    t.bigint "parent_id"
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["parent_id"], name: "index_finance_categories_on_parent_id"
    t.index ["user_id", "kind"], name: "index_finance_categories_on_user_id_and_kind"
    t.index ["user_id", "position"], name: "index_finance_categories_on_user_id_and_position"
    t.index ["user_id"], name: "index_finance_categories_on_user_id"
  end

  create_table "focus_sessions", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "duration_seconds", default: 1500, null: false
    t.string "mode", default: "focus", null: false
    t.datetime "started_at", null: false
    t.bigint "todo_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["todo_id"], name: "index_focus_sessions_on_todo_id"
    t.index ["user_id", "started_at"], name: "index_focus_sessions_on_user_id_and_started_at"
    t.index ["user_id"], name: "index_focus_sessions_on_user_id"
  end

  create_table "goals", force: :cascade do |t|
    t.string "color", default: "#B8860B"
    t.datetime "created_at", null: false
    t.decimal "current_value", precision: 14, scale: 2, default: "0.0", null: false
    t.date "deadline"
    t.text "description"
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.bigint "related_id"
    t.string "related_type"
    t.string "status", default: "active", null: false
    t.string "target_type", default: "custom", null: false
    t.decimal "target_value", precision: 14, scale: 2, default: "0.0", null: false
    t.string "unit", default: "TRY"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["related_type", "related_id"], name: "index_goals_on_related"
    t.index ["user_id", "status", "position"], name: "index_goals_on_user_id_and_status_and_position"
    t.index ["user_id"], name: "index_goals_on_user_id"
  end

  create_table "habit_logs", force: :cascade do |t|
    t.boolean "completed", default: false, null: false
    t.integer "count", default: 0, null: false
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.bigint "habit_id", null: false
    t.text "note"
    t.datetime "updated_at", null: false
    t.index ["habit_id", "date"], name: "index_habit_logs_on_habit_id_and_date", unique: true
    t.index ["habit_id"], name: "index_habit_logs_on_habit_id"
  end

  create_table "habits", force: :cascade do |t|
    t.datetime "archived_at"
    t.string "color", default: "#B8860B"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "frequency", default: "daily", null: false
    t.bigint "goal_id"
    t.string "name", null: false
    t.integer "target_count", default: 1, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["goal_id"], name: "index_habits_on_goal_id"
    t.index ["user_id", "archived_at"], name: "index_habits_on_user_id_and_archived_at"
    t.index ["user_id"], name: "index_habits_on_user_id"
  end

  create_table "journal_entries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.integer "energy_level"
    t.text "gratitude"
    t.string "mood"
    t.string "tags"
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "weather"
    t.index ["user_id", "date"], name: "index_journal_entries_on_user_id_and_date"
    t.index ["user_id"], name: "index_journal_entries_on_user_id"
  end

  create_table "subscriptions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.boolean "active", default: true, null: false
    t.integer "amount_cents", default: 0, null: false
    t.string "color", default: "#B8860B"
    t.datetime "created_at", null: false
    t.date "end_date"
    t.bigint "finance_category_id"
    t.string "frequency", default: "monthly", null: false
    t.bigint "goal_id"
    t.string "name", null: false
    t.date "next_charge_on"
    t.text "note"
    t.date "start_date"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "vendor"
    t.index ["account_id"], name: "index_subscriptions_on_account_id"
    t.index ["finance_category_id"], name: "index_subscriptions_on_finance_category_id"
    t.index ["goal_id"], name: "index_subscriptions_on_goal_id"
    t.index ["user_id", "active", "next_charge_on"], name: "index_subscriptions_on_user_id_and_active_and_next_charge_on"
    t.index ["user_id"], name: "index_subscriptions_on_user_id"
  end

  create_table "taggings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "tag_id", null: false
    t.bigint "taggable_id", null: false
    t.string "taggable_type", null: false
    t.datetime "updated_at", null: false
    t.index ["tag_id", "taggable_type", "taggable_id"], name: "index_taggings_on_tag_id_and_taggable_type_and_taggable_id", unique: true
    t.index ["tag_id"], name: "index_taggings_on_tag_id"
    t.index ["taggable_type", "taggable_id"], name: "index_taggings_on_taggable"
  end

  create_table "tags", force: :cascade do |t|
    t.string "color", default: "#A09B8E"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "slug"], name: "index_tags_on_user_id_and_slug", unique: true
    t.index ["user_id"], name: "index_tags_on_user_id"
  end

  create_table "todo_lists", force: :cascade do |t|
    t.datetime "archived_at"
    t.string "color", default: "#B8860B"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "position"], name: "index_todo_lists_on_user_id_and_position"
    t.index ["user_id"], name: "index_todo_lists_on_user_id"
  end

  create_table "todos", force: :cascade do |t|
    t.text "body"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "due_at"
    t.bigint "goal_id"
    t.bigint "parent_id"
    t.integer "position", default: 0, null: false
    t.string "priority", default: "medium", null: false
    t.text "recurrence_rule"
    t.boolean "recurring", default: false, null: false
    t.string "status", default: "pending", null: false
    t.string "title", null: false
    t.bigint "todo_list_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["goal_id"], name: "index_todos_on_goal_id"
    t.index ["parent_id"], name: "index_todos_on_parent_id"
    t.index ["todo_list_id", "position"], name: "index_todos_on_todo_list_id_and_position"
    t.index ["todo_list_id"], name: "index_todos_on_todo_list_id"
    t.index ["user_id", "status", "due_at"], name: "index_todos_on_user_id_and_status_and_due_at"
    t.index ["user_id"], name: "index_todos_on_user_id"
  end

  create_table "transactions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.integer "amount_cents", default: 0, null: false
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.string "description"
    t.bigint "finance_category_id"
    t.string "kind", null: false
    t.text "note"
    t.datetime "occurred_at"
    t.bigint "parent_transaction_id"
    t.text "recurrence_rule"
    t.boolean "recurring", default: false, null: false
    t.bigint "related_account_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["account_id", "date"], name: "index_transactions_on_account_id_and_date"
    t.index ["account_id"], name: "index_transactions_on_account_id"
    t.index ["finance_category_id"], name: "index_transactions_on_finance_category_id"
    t.index ["parent_transaction_id"], name: "index_transactions_on_parent_transaction_id"
    t.index ["related_account_id"], name: "index_transactions_on_related_account_id"
    t.index ["user_id", "date"], name: "index_transactions_on_user_id_and_date"
    t.index ["user_id", "kind", "date"], name: "index_transactions_on_user_id_and_kind_and_date"
    t.index ["user_id"], name: "index_transactions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency", default: "TRY", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "locale", default: "tr", null: false
    t.string "name"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.string "theme_preference", default: "system", null: false
    t.string "timezone", default: "Istanbul", null: false
    t.datetime "updated_at", null: false
    t.integer "weekly_review_day", default: 0, null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "weekly_reviews", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "reflection_learned"
    t.text "reflection_next_week"
    t.text "reflection_went_well"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.date "week_starting", null: false
    t.index ["user_id", "week_starting"], name: "index_weekly_reviews_on_user_id_and_week_starting", unique: true
    t.index ["user_id"], name: "index_weekly_reviews_on_user_id"
  end

  add_foreign_key "accounts", "users"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "backups", "users"
  add_foreign_key "budgets", "finance_categories"
  add_foreign_key "budgets", "users"
  add_foreign_key "events", "users"
  add_foreign_key "finance_categories", "finance_categories", column: "parent_id"
  add_foreign_key "finance_categories", "users"
  add_foreign_key "focus_sessions", "todos"
  add_foreign_key "focus_sessions", "users"
  add_foreign_key "goals", "users"
  add_foreign_key "habit_logs", "habits"
  add_foreign_key "habits", "goals"
  add_foreign_key "habits", "users"
  add_foreign_key "journal_entries", "users"
  add_foreign_key "subscriptions", "accounts"
  add_foreign_key "subscriptions", "finance_categories"
  add_foreign_key "subscriptions", "goals"
  add_foreign_key "subscriptions", "users"
  add_foreign_key "taggings", "tags"
  add_foreign_key "tags", "users"
  add_foreign_key "todo_lists", "users"
  add_foreign_key "todos", "goals"
  add_foreign_key "todos", "todo_lists"
  add_foreign_key "todos", "todos", column: "parent_id"
  add_foreign_key "todos", "users"
  add_foreign_key "transactions", "accounts"
  add_foreign_key "transactions", "accounts", column: "related_account_id"
  add_foreign_key "transactions", "finance_categories"
  add_foreign_key "transactions", "transactions", column: "parent_transaction_id"
  add_foreign_key "transactions", "users"
  add_foreign_key "weekly_reviews", "users"
end
