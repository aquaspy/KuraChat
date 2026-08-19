require "test_helper"

class ShareFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "you@x.com", password: "secret-ok")
    @chat = @user.conversations.create!(title: "Picnic")
    @chat.messages.create!(role: "user", content: "Where?")
    @chat.messages.create!(role: "assistant", status: "complete", content: "The park.")
    post login_path, params: { email: @user.email, password: "secret-ok" }
  end

  test "create copy rotate and revoke a read-only share link" do
    post conversation_share_path(@chat)
    @chat.reload
    assert @chat.shared?
    token = @chat.share_token

    get shared_conversation_path(token)
    assert_response :success
    assert_includes @response.body, "The park."
    assert_includes @response.body, "noindex"
    assert_no_match(/class="composer"/, @response.body)
    assert_no_match(/name="content"/, @response.body)

    patch conversation_share_path(@chat)
    @chat.reload
    assert_not_equal token, @chat.share_token
    get shared_conversation_path(token)
    assert_response :not_found

    delete conversation_share_path(@chat)
    assert_not @chat.reload.shared?
  end

  test "unauthenticated visitor can read a shared chat" do
    @chat.generate_share_token!
    delete logout_path
    get shared_conversation_path(@chat.share_token)
    assert_response :success
    assert_includes @response.body, "Picnic"
  end
end
