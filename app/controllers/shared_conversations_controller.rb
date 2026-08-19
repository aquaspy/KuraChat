class SharedConversationsController < ApplicationController
  allow_unauthenticated_access
  skip_unlock

  def show
    @conversation = Conversation.find_by!(share_token: params[:token])
    @messages = @conversation.messages.transcript.chronological
    response.set_header("X-Robots-Tag", "noindex, nofollow, noarchive")
    response.set_header("Referrer-Policy", "no-referrer")
  end
end
