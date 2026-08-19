class CreateMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :messages do |t|
      t.references :conversation, null: false, foreign_key: true
      t.string :role, null: false
      t.text :content
      t.boolean :web, null: false, default: false
      t.string :status
      t.json :citations
      t.json :token_usage
      t.json :raw
      t.string :error
      t.timestamps
    end
    add_index :messages, [ :conversation_id, :id ]
    add_index :messages, :conversation_id,
      unique: true,
      where: "role = 'assistant' AND status IN ('pending', 'streaming')",
      name: "index_messages_one_inflight_per_conversation"
  end
end
