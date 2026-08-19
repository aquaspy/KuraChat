class User < ApplicationRecord
  has_secure_password
  has_many :conversations, dependent: :destroy

  normalizes :email, with: -> { it.strip.downcase }

  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8 }, allow_nil: true
end
