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

  def chat_cost_label(conversation)
    TokenCost.format_usd(conversation.estimated_api_cost)
  end

  def chat_cost_i18n_key(conversation)
    conversation.api_cost_billed? ? "chat.cost" : "chat.cost_est"
  end

  def message_image_tag(image)
    thumb = image.variant(resize_to_limit: [ 720, 720 ]).processed
    image_tag thumb, alt: ""
  rescue StandardError
    image_tag image, alt: ""
  end
end
