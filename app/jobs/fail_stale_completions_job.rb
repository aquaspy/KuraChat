class FailStaleCompletionsJob < ApplicationJob
  STALE_AFTER = 5.minutes

  def perform
    Message.where(role: "assistant", status: %w[pending streaming])
      .where("updated_at < ?", STALE_AFTER.ago)
      .find_each do |message|
        message.update!(status: "failed", error: "stale")
        ChatCompleter.broadcast_failed(message)
      end
  end
end
