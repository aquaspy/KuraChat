module ApplicationHelper
  def signup_enabled?
    Kura.signup_enabled?
  end

  def safe_citation_url(url)
    uri = URI.parse(url.to_s)
    uri if uri.is_a?(URI::HTTP)
  rescue URI::InvalidURIError
    nil
  end

  def conversation_inflight?(conversation)
    conversation.messages.where(role: "assistant", status: %w[pending streaming]).exists?
  end

  def message_image_tag(message)
    return unless message.image.attached?

    thumb = message.image.variant(resize_to_limit: [ 720, 720 ]).processed
    image_tag thumb, alt: ""
  rescue StandardError
    image_tag message.image, alt: ""
  end
end
