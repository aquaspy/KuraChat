class SharesController < ApplicationController
  before_action :set_conversation

  def create
    @conversation.generate_share_token! unless @conversation.shared?
    render_change
  end

  def update
    @conversation.generate_share_token!
    render_change
  end

  def destroy
    @conversation.revoke_share_token!
    render_change
  end

  private
    def set_conversation
      @conversation = current_user.conversations.find(params[:conversation_id])
    end

    def render_change
      respond_to do |format|
        format.turbo_stream { render :update }
        format.html { redirect_to conversation_path(@conversation, q: params[:q]) }
      end
    end
end
