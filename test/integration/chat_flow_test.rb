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

  test "delete all removes only the current users chats" do
    keep = @other.conversations.create!(title: "Theirs")
    mine = @user.conversations.create!(title: "Mine")
    mine.messages.create!(role: "user", content: "secret")

    delete destroy_all_conversations_path
    assert_redirected_to conversations_path
    assert_not Conversation.exists?(mine.id)
    assert_not Message.exists?(conversation_id: mine.id)
    assert Conversation.exists?(keep.id)
  end

  test "search filters titles" do
    @user.conversations.create!(title: "Garden")
    @user.conversations.create!(title: "Taxes")
    get conversations_path, params: { q: "Tax" }
    assert_includes @response.body, "Taxes"
    assert_not_includes @response.body, "Garden"
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
end
