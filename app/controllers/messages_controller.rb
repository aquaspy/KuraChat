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
      @user_message = @conversation.messages.new(
        role: "user",
        content: params[:content].to_s,
        web: ActiveModel::Type::Boolean.new.cast(params[:web]) || false
      )
      @user_message.image.attach(params[:image]) if params[:image].present?
      @user_message.save!
      @assistant = @conversation.messages.create!(role: "assistant", status: "pending", content: "")
    end
    CompleteChatJob.perform_later(@assistant.id, I18n.locale.to_s)
    @query = params[:q].to_s.strip
    @conversations = current_user.conversations.order(updated_at: :desc)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @conversation }
    end
  rescue ActiveRecord::RecordNotUnique
    redirect_to @conversation, alert: t("chat.in_flight")
  rescue ActiveRecord::RecordInvalid
    alert = @user_message&.errors&.[](:image).present? ? t("chat.bad_image") : t("chat.blank")
    redirect_to @conversation, alert: alert
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
    CompleteChatJob.perform_later(@message.id, I18n.locale.to_s)
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
end
