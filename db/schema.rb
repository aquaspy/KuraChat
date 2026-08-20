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

ActiveRecord::Schema[8.1].define(version: 2026_08_20_120000) do
  create_table "conversations", force: :cascade do |t|
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.string "share_token"
    t.integer "summarized_through_id"
    t.text "summary"
    t.string "title", default: "", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["share_token"], name: "index_conversations_on_share_token", unique: true
    t.index ["user_id", "updated_at"], name: "index_conversations_on_user_id_and_updated_at"
    t.index ["user_id"], name: "index_conversations_on_user_id"
  end

  create_table "messages", force: :cascade do |t|
    t.json "citations"
    t.text "content"
    t.integer "conversation_id", null: false
    t.datetime "created_at", null: false
    t.string "error"
    t.json "raw"
    t.string "role", null: false
    t.string "status"
    t.json "token_usage"
    t.datetime "updated_at", null: false
    t.boolean "web", default: false, null: false
    t.index ["conversation_id", "id"], name: "index_messages_on_conversation_id_and_id"
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
    t.index ["conversation_id"], name: "index_messages_one_inflight_per_conversation", unique: true, where: "role = 'assistant' AND status IN ('pending', 'streaming')"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "auto_lock", default: false, null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "conversations", "users"
  add_foreign_key "messages", "conversations"
end
