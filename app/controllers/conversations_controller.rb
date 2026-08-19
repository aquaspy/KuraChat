class ConversationsController < ApplicationController
  before_action :set_conversation, only: %i[show update destroy]

  def index
    load_list
  end

  def show
    load_list
    @messages = @conversation.messages.transcript.chronological
  end

  def create
    conversation = current_user.conversations.create!
    redirect_to conversation
  end

  def update
    @conversation.update!(conversation_params)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @conversation }
    end
  end

  def destroy
    @conversation.destroy
    Conversation.reclaim_space
    redirect_to conversations_path, notice: t("chat.deleted")
  end

  def destroy_all
    ids = current_user.conversation_ids
    Message.where(conversation_id: ids).delete_all
    current_user.conversations.delete_all
    Conversation.reclaim_space
    redirect_to conversations_path, notice: t("chat.deleted_all")
  end

  private
    def set_conversation
      @conversation = current_user.conversations.find(params[:id])
    end

    def load_list
      @query = params[:q].to_s.strip
      scope = current_user.conversations.order(updated_at: :desc)
      scope = scope.where("title LIKE ?", "%#{Conversation.sanitize_sql_like(@query)}%") if @query.present?
      @conversations = scope
    end

    def conversation_params
      params.require(:conversation).permit(:title)
    end
end
