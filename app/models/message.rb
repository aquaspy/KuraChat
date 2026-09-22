require "base64"

class Message < ApplicationRecord
  ROLES = %w[user assistant system tool].freeze
  STATUSES = %w[pending streaming complete failed].freeze
  IMAGE_TYPES = %w[image/jpeg image/png image/webp image/heic image/heif image/gif].freeze
  IMAGE_MAX_BYTES = 8.megabytes
  MAX_IMAGES = 4
  IMAGE_TOKENS = 2_000
  MODEL_VARIANT = { resize_to_limit: [ 1568, 1568 ], format: :jpeg, saver: { quality: 85 } }.freeze

  belongs_to :conversation, touch: true
  has_many_attached :images, dependent: false
  attribute :web, :boolean, default: false

  # Prepend: must run before the dependent: :destroy underneath
  # has_many_attached, which deletes attachment rows without blobs.
  before_destroy :purge_images, prepend: true

  validates :role, inclusion: { in: ROLES }
  validates :content, length: { maximum: 16_384 }, if: -> { role == "user" }
  validate :user_content_present
  validate :acceptable_images

  scope :chronological, -> { order(:id) }
  scope :transcript, -> {
    where(role: "user").or(
      where(role: "assistant", status: %w[pending streaming failed])
    ).or(
      where(role: "assistant", status: "complete").where.not(content: [ nil, "" ])
    )
  }

  def visible_in_ui?
    return true if role == "user"
    return false unless role == "assistant"
    return true if status.in?(%w[pending streaming failed])

    status == "complete" && content.present?
  end

  def inflight?
    role == "assistant" && status.in?(%w[pending streaming])
  end

  def failed?
    role == "assistant" && status == "failed"
  end

  def tool_calls?
    raw.is_a?(Hash) && raw["tool_calls"].present?
  end

  def as_input
    return nil unless role.in?(%w[user assistant])
    return nil if role == "assistant" && (status != "complete" || content.blank?)

    items = []
    if role == "assistant"
      Array(raw.is_a?(Hash) ? raw["reasoning"] : nil).each do |item|
        items << item if item.is_a?(Hash)
      end
    end
    items << { role: role, content: input_content }
    items
  end

  def input_cost
    return 0 unless role.in?(%w[user assistant])
    return 0 if role == "assistant" && (status != "complete" || content.blank?)

    cost = 0
    if role == "assistant"
      Array(raw.is_a?(Hash) ? raw["reasoning"] : nil).each do |item|
        cost += token_bytes(item.to_json)
      end
    end
    cost += IMAGE_TOKENS * images.size if role == "user" && images.attached?
    cost += token_bytes(user_text_for_model) if role == "user"
    cost += token_bytes(content.to_s) if role == "assistant"
    cost
  end

  private
    def purge_images
      images.each(&:purge) if images.attached?
    end

    def user_content_present
      return unless role == "user"
      return if images.attached?

      errors.add(:content, :blank) if content.to_s.strip.blank?
    end

    def acceptable_images
      return unless images.attached?

      errors.add(:images, :too_many, count: MAX_IMAGES) if images.size > MAX_IMAGES
      images.each do |image|
        errors.add(:images, :invalid) unless image.content_type.in?(IMAGE_TYPES)
        errors.add(:images, :invalid) if image.byte_size > IMAGE_MAX_BYTES
      end
    end

    def input_content
      return content if content.is_a?(Array)
      return content.to_s unless role == "user" && images.attached?

      parts = images.filter_map { |image|
        uri = image_data_uri(image)
        uri.present? ? { type: "input_image", image_url: uri, detail: "high" } : nil
      }
      return content.to_s if parts.empty?

      parts << { type: "input_text", text: user_text_for_model }
    end

    def user_text_for_model
      text = content.to_s.strip
      return text if text.present?
      return I18n.t("chat.image_prompt") if images.attached?

      text
    end

    def image_data_uri(image)
      begin
        bytes = image.variant(MODEL_VARIANT).processed.download
        "data:image/jpeg;base64,#{Base64.strict_encode64(bytes)}"
      rescue StandardError
        mime = image.content_type.to_s
        mime = "image/png" unless mime.in?(%w[image/jpeg image/png image/gif])
        "data:#{mime};base64,#{Base64.strict_encode64(image.download)}"
      end
    end

    def token_bytes(str)
      (str.to_s.bytesize / 4.0).ceil
    end
end
