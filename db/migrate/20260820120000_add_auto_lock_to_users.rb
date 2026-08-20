class AddAutoLockToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :auto_lock, :boolean, default: false, null: false
  end
end
