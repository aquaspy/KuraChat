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

    get conversations_path
    assert_response :success

    patch conversation_path(chat), params: { conversation: { title: "Taxes" } }
    assert_equal "Taxes", chat.reload.title

    delete conversation_path(chat)
    assert_redirected_to conversations_path
    assert_not Conversation.exists?(chat.id)
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
end
