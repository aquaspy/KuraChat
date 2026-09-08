class RemoveAutoLockFromUsers < ActiveRecord::Migration[8.1]
  def change
    remove_column :users, :auto_lock, :boolean, default: false, null: false
  end
end
