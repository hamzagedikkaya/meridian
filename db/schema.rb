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

ActiveRecord::Schema[8.0].define(version: 2026_05_20_160941) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "accounts", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.string "account_type", default: "cash", null: false
    t.string "currency", default: "TRY", null: false
    t.integer "initial_balance_cents", default: 0, null: false
    t.string "color", default: "#B8860B"
    t.string "icon"
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "archived_at"], name: "index_accounts_on_user_id_and_archived_at"
    t.index ["user_id"], name: "index_accounts_on_user_id"
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "finance_categories", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.string "color", default: "#A09B8E"
    t.string "icon"
    t.string "kind", default: "expense", null: false
    t.bigint "parent_id"
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["parent_id"], name: "index_finance_categories_on_parent_id"
    t.index ["user_id", "kind"], name: "index_finance_categories_on_user_id_and_kind"
    t.index ["user_id", "position"], name: "index_finance_categories_on_user_id_and_position"
    t.index ["user_id"], name: "index_finance_categories_on_user_id"
  end

  create_table "subscriptions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "account_id", null: false
    t.bigint "finance_category_id"
    t.string "name", null: false
    t.string "vendor"
    t.integer "amount_cents", default: 0, null: false
    t.string "frequency", default: "monthly", null: false
    t.date "next_charge_on"
    t.date "start_date"
    t.date "end_date"
    t.boolean "active", default: true, null: false
    t.string "color", default: "#B8860B"
    t.string "icon"
    t.text "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_subscriptions_on_account_id"
    t.index ["finance_category_id"], name: "index_subscriptions_on_finance_category_id"
    t.index ["user_id", "active", "next_charge_on"], name: "index_subscriptions_on_user_id_and_active_and_next_charge_on"
    t.index ["user_id"], name: "index_subscriptions_on_user_id"
  end

  create_table "todo_lists", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.string "color", default: "#B8860B"
    t.string "icon"
    t.integer "position", default: 0, null: false
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "position"], name: "index_todo_lists_on_user_id_and_position"
    t.index ["user_id"], name: "index_todo_lists_on_user_id"
  end

  create_table "todos", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "todo_list_id"
    t.string "title", null: false
    t.text "body"
    t.datetime "due_at"
    t.string "priority", default: "medium", null: false
    t.string "status", default: "pending", null: false
    t.integer "position", default: 0, null: false
    t.datetime "completed_at"
    t.boolean "recurring", default: false, null: false
    t.text "recurrence_rule"
    t.bigint "parent_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["parent_id"], name: "index_todos_on_parent_id"
    t.index ["todo_list_id", "position"], name: "index_todos_on_todo_list_id_and_position"
    t.index ["todo_list_id"], name: "index_todos_on_todo_list_id"
    t.index ["user_id", "status", "due_at"], name: "index_todos_on_user_id_and_status_and_due_at"
    t.index ["user_id"], name: "index_todos_on_user_id"
  end

  create_table "transactions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "account_id", null: false
    t.bigint "finance_category_id"
    t.bigint "related_account_id"
    t.integer "amount_cents", default: 0, null: false
    t.string "kind", null: false
    t.string "description"
    t.text "note"
    t.date "date", null: false
    t.datetime "occurred_at"
    t.boolean "recurring", default: false, null: false
    t.text "recurrence_rule"
    t.bigint "parent_transaction_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.string "name"
    t.string "timezone", default: "Istanbul", null: false
    t.string "currency", default: "TRY", null: false
    t.string "locale", default: "tr", null: false
    t.string "theme_preference", default: "system", null: false
    t.integer "weekly_review_day", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "accounts", "users"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "finance_categories", "finance_categories", column: "parent_id"
  add_foreign_key "finance_categories", "users"
  add_foreign_key "subscriptions", "accounts"
  add_foreign_key "subscriptions", "finance_categories"
  add_foreign_key "subscriptions", "users"
  add_foreign_key "todo_lists", "users"
  add_foreign_key "todos", "todo_lists"
  add_foreign_key "todos", "todos", column: "parent_id"
  add_foreign_key "todos", "users"
  add_foreign_key "transactions", "accounts"
  add_foreign_key "transactions", "accounts", column: "related_account_id"
  add_foreign_key "transactions", "finance_categories"
  add_foreign_key "transactions", "transactions", column: "parent_transaction_id"
  add_foreign_key "transactions", "users"
end
