require "test_helper"

class ChatFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user = User.create!(email: "you@x.com", password: "secret-ok")
    @other = User.create!(email: "them@x.com", password: "secret-ok")
    post login_path, params: { email: @user.email, password: "secret-ok" }
  end

  test "create list rename and delete a conversation" do
    post conversations_path
    chat = @user.conversations.last
    assert_redirected_to conversation_path(chat)

    patch conversation_path(chat), params: { conversation: { title: "Taxes" } }
    assert_equal "Taxes", chat.reload.title

    get conversations_path
    assert_response :success
    assert_includes @response.body, "Taxes"

    delete conversation_path(chat)
    assert_redirected_to conversations_path
    assert_not Conversation.exists?(chat.id)
  end

  test "new chat reuses an empty untitled draft" do
    post conversations_path
    first = @user.conversations.last
    post conversations_path
    assert_redirected_to conversation_path(first)
    assert_equal 1, @user.conversations.count
  end

  test "new chat opens a fresh conversation after a message" do
    post conversations_path
    first = @user.conversations.last
    first.messages.create!(role: "user", content: "Hi")
    post conversations_path
    assert_equal 2, @user.conversations.count
    assert_not_equal first.id, @user.conversations.order(:id).last.id
  end

  test "new chat does not reuse a named empty conversation" do
    named = @user.conversations.create!(title: "Notes")
    post conversations_path
    assert_not_equal named.id, @user.conversations.order(:id).last.id
    assert_equal 2, @user.conversations.count
  end

  test "leaving an empty chat discards the untitled draft" do
    post conversations_path
    draft = @user.conversations.last
    get conversations_path
    assert_not Conversation.exists?(draft.id)
  end

  test "opening another chat discards an abandoned untitled draft" do
    keep = @user.conversations.create!(title: "Keep")
    keep.messages.create!(role: "user", content: "hello")
    post conversations_path
    draft = @user.conversations.where.not(id: keep.id).last
    get conversation_path(keep)
    assert_not Conversation.exists?(draft.id)
    assert Conversation.exists?(keep.id)
  end

  test "conversation bar shows estimated cost after stored usage" do
    post conversations_path
    chat = @user.conversations.last
    chat.messages.create!(
      role: "assistant",
      status: "complete",
      content: "Hello",
      token_usage: {
        "input_tokens" => 80_000, "cached_tokens" => 0, "output_tokens" => 20_000,
        "reasoning_tokens" => 0, "cost_in_usd_ticks" => 1_250_000_000
      }
    )
    get conversation_path(chat)
    assert_response :success
    assert_includes @response.body, "chat-cost"
    assert_includes @response.body, TokenCost.format_usd(chat.estimated_api_cost)
    assert_not_includes @response.body, "est. $0.12"
  end

  test "portuguese locale labels a blank title as Sem título" do
    post conversations_path
    chat = @user.conversations.last
    get conversation_path(chat), headers: { "HTTP_ACCEPT_LANGUAGE" => "pt-BR,pt;q=0.9" }
    assert_response :success
    assert_includes @response.body, "Sem título"
    assert_not_includes @response.body, "Untitled"
  end

  test "stranger cannot open another users chat" do
    chat = @other.conversations.create!(title: "Secret")
    get conversation_path(chat)
    assert_response :not_found
  end

  test "web flag on later messages follows the first user turn" do
    chat = @user.conversations.create!
    assert_enqueued_jobs 2, only: CompleteChatJob do
      post conversation_messages_path(chat), params: { content: "News?", web: "1" }
      chat.messages.where(role: "assistant").update_all(status: "complete", content: "ok")
      post conversation_messages_path(chat), params: { content: "And now?", web: "0" }
    end
    assert_equal [ true, true ], chat.messages.where(role: "user").order(:id).pluck(:web)
  end

  test "web stays off when the first turn omitted it" do
    chat = @user.conversations.create!
    assert_enqueued_jobs 2, only: CompleteChatJob do
      post conversation_messages_path(chat), params: { content: "Hi" }
      chat.messages.where(role: "assistant").update_all(status: "complete", content: "ok")
      post conversation_messages_path(chat), params: { content: "News?", web: "1" }
    end
    assert_equal [ false, false ], chat.messages.where(role: "user").order(:id).pluck(:web)
  end

  test "open chat with a user message shows a locked web switch" do
    chat = @user.conversations.create!
    chat.messages.create!(role: "user", content: "News?", web: true)
    get conversation_path(chat)
    assert_response :success
    assert_includes @response.body, "is-locked"
    assert_includes @response.body, "Web stays on"
  end

  test "posting a message enqueues completion" do
    chat = @user.conversations.create!
    assert_enqueued_with(job: CompleteChatJob) do
      post conversation_messages_path(chat), params: { content: "Hello" }
    end
    assert_equal 1, chat.messages.where(role: "user").count
    assert_equal "pending", chat.messages.where(role: "assistant").last.status
  end

  test "second message while inflight is rejected" do
    chat = @user.conversations.create!
    chat.messages.create!(role: "user", content: "Hi")
    chat.messages.create!(role: "assistant", status: "streaming", content: "")
    post conversation_messages_path(chat), params: { content: "Again" }
    assert_redirected_to conversation_path(chat)
    follow_redirect!
    assert_match(/Wait|Espere/i, flash[:alert].to_s + @response.body)
    assert_equal 1, chat.messages.where(role: "user").count
  end

  test "posting an image-only message enqueues completion" do
    chat = @user.conversations.create!
    file = fixture_file_upload("dot.png", "image/png")
    assert_enqueued_with(job: CompleteChatJob) do
      post conversation_messages_path(chat), params: { content: "", image: file }
    end
    user = chat.messages.find_by!(role: "user")
    assert user.image.attached?
    assert_equal "pending", chat.messages.where(role: "assistant").last.status
  end

  test "delete all purges images and only the current users chats" do
    keep = @other.conversations.create!(title: "Theirs")
    mine = @user.conversations.create!(title: "Mine")
    pic = mine.messages.create!(role: "user", content: "secret")
    pic.image.attach(io: File.open(Rails.root.join("test/fixtures/files/dot.png"), "rb"), filename: "dot.png", content_type: "image/png")
    path = pic.image.blob.service.path_for(pic.image.blob.key)
    assert File.exist?(path)

    delete destroy_all_conversations_path
    assert_redirected_to conversations_path
    assert_not Conversation.exists?(mine.id)
    assert_not Message.exists?(conversation_id: mine.id)
    assert Conversation.exists?(keep.id)
    assert_not File.exist?(path)
  end

  test "search filters titles" do
    @user.conversations.create!(title: "Garden")
    @user.conversations.create!(title: "Taxes")
    get conversations_path, params: { q: "Tax" }
    assert_includes @response.body, "Taxes"
    assert_not_includes @response.body, "Garden"
    assert_includes @response.body, %(target="_top")
  end

  test "search frame filters titles without discarding a draft" do
    post conversations_path
    draft = @user.conversations.last
    @user.conversations.create!(title: "Garden")
    @user.conversations.create!(title: "Taxes")

    get conversations_path, params: { q: "Tax" }, headers: { "Turbo-Frame" => "conversation-search" }
    assert_response :success
    assert_includes @response.body, "Taxes"
    assert_not_includes @response.body, "Garden"
    assert_includes @response.body, %(id="conversation-search")
    assert_includes @response.body, %(target="_top")
    assert_not_includes @response.body, "col-editor"
    assert Conversation.exists?(draft.id)
  end

  test "new chat composer autofocuses and title field is streamable" do
    post conversations_path
    chat = @user.conversations.last
    get conversation_path(chat)
    assert_response :success
    assert_includes @response.body, "autofocus"
    assert_includes @response.body, %(id="title_field_conversation_#{chat.id}")
  end

  test "composer re-syncs the send button as the user types" do
    chat = @user.conversations.create!
    get conversation_path(chat)
    assert_response :success
    assert_includes @response.body, %(input-&gt;composer#resize input-&gt;composer#sync)
  end
end
