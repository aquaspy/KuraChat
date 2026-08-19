class CreateConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :conversations do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false, default: ""
      t.string :share_token
      t.datetime :archived_at
      t.timestamps
    end
    add_index :conversations, [ :user_id, :updated_at ]
    add_index :conversations, :share_token, unique: true
  end
end
