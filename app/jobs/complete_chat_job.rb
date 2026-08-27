class CompleteChatJob < ApplicationJob
  limits_concurrency to: 1,
    key: ->(id, *) { "conversation-#{Message.find_by(id:)&.conversation_id || id}" },
    duration: 70.minutes

  def perform(assistant_message_id, locale = I18n.default_locale.to_s, region = nil)
    I18n.with_locale(locale) do
      message = Message.find_by(id: assistant_message_id)
      return if message.nil?
      return unless message.status.in?(%w[pending streaming])

      ChatCompleter.new(message, locale: locale, region: region).run
    end
  end
end
