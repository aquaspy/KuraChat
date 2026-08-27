class MessagesController < ApplicationController
  before_action :set_conversation
  rate_limit to: 30, within: 5.minutes, only: %i[create retry],
    by: -> { current_user.id },
    with: -> { redirect_back_or_to conversation_path(@conversation), alert: t("chat.too_many") }

  def create
    @user_message = nil
    @assistant = nil
    Conversation.transaction do
      @conversation.lock!
      if @conversation.messages.where(role: "assistant", status: %w[pending streaming]).exists?
        redirect_to @conversation, alert: t("chat.in_flight")
        return
      end
      @user_message = @conversation.messages.create!(
        role: "user",
        content: params[:content].to_s,
        web: ActiveModel::Type::Boolean.new.cast(params[:web]) || false
      )
      @assistant = @conversation.messages.create!(role: "assistant", status: "pending", content: "")
    end
    CompleteChatJob.perform_later(@assistant.id, I18n.locale.to_s, search_region)
    @query = params[:q].to_s.strip
    @conversations = current_user.conversations.order(updated_at: :desc)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @conversation }
    end
  rescue ActiveRecord::RecordNotUnique
    redirect_to @conversation, alert: t("chat.in_flight")
  rescue ActiveRecord::RecordInvalid
    redirect_to @conversation, alert: t("chat.blank")
  end

  def retry
    Conversation.transaction do
      @conversation.lock!
      if @conversation.messages.where(role: "assistant", status: %w[pending streaming]).exists?
        redirect_to @conversation, alert: t("chat.in_flight")
        return
      end
      @message = @conversation.messages.find(params[:id])
      unless @message.role == "assistant" && @message.status == "failed"
        redirect_to @conversation, alert: t("chat.cannot_retry")
        return
      end
      @message.update!(status: "pending", error: nil, content: "")
    end
    CompleteChatJob.perform_later(@message.id, I18n.locale.to_s, search_region)
    respond_to do |format|
      format.turbo_stream { render :retry }
      format.html { redirect_to @conversation }
    end
  rescue ActiveRecord::RecordNotUnique
    redirect_to @conversation, alert: t("chat.in_flight")
  end

  private
    def set_conversation
      @conversation = current_user.conversations.find(params[:conversation_id])
    end

    def search_region
      WebSearch.region_from_header(request.headers["Accept-Language"])
    end
end
