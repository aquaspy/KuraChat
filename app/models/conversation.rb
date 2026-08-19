class Conversation < ApplicationRecord
  belongs_to :user
  has_many :messages, dependent: :delete_all

  def untitled?
    title.blank?
  end

  def display_title
    title.presence || I18n.t("js.untitled")
  end

  def shared?
    share_token.present?
  end

  def generate_share_token!
    5.times do
      token = SecureRandom.urlsafe_base64(18)
      update!(share_token: token)
      return share_token
    rescue ActiveRecord::RecordNotUnique
      next
    end
    raise "Could not generate a share token"
  end

  def revoke_share_token!
    update!(share_token: nil)
  end

  def self.reclaim_space
    return if Message.where(status: %w[pending streaming]).exists?

    connection.execute("VACUUM")
  rescue ActiveRecord::StatementInvalid, SQLite3::Exception
    nil
  end
end
