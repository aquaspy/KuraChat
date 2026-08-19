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
end
