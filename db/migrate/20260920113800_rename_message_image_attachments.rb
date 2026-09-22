class RenameMessageImageAttachments < ActiveRecord::Migration[8.1]
  def up
    ActiveStorage::Attachment.where(record_type: "Message", name: "image").update_all(name: "images")
  end

  def down
    ActiveStorage::Attachment.where(record_type: "Message", name: "images").update_all(name: "image")
  end
end
