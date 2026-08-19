class AddSummaryToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :summary, :text
    add_column :conversations, :summarized_through_id, :integer
  end
end
