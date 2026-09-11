require "test_helper"

class MessageTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "you@x.com", password: "secret-ok")
    @chat = @user.conversations.create!
  end

  test "as_input keeps visible turns and drops placeholders and old tool rows" do
    pending = @chat.messages.create!(role: "assistant", status: "pending", content: "")
    assert_nil pending.as_input

    hidden = @chat.messages.create!(
      role: "assistant",
      status: "complete",
      content: nil,
      raw: { "tool_calls" => [ { "id" => "c1", "type" => "function", "function" => { "name" => "web_search", "arguments" => "{}" } } ] }
    )
    assert_nil hidden.as_input

    tool = @chat.messages.create!(role: "tool", content: "{}", raw: { "tool_call_id" => "c1" })
    assert_nil tool.as_input

    user = @chat.messages.create!(role: "user", content: "Hi")
    assert_equal({ role: "user", content: "Hi" }, user.as_input)

    assistant = @chat.messages.create!(role: "assistant", status: "complete", content: "Hello")
    assert_equal({ role: "assistant", content: "Hello" }, assistant.as_input)
  end

  test "user content is capped" do
    msg = @chat.messages.new(role: "user", content: "x" * 16_385)
    assert_not msg.valid?
  end

  test "assistant content is not capped at 16384" do
    msg = @chat.messages.new(role: "assistant", status: "complete", content: "x" * 20_000)
    assert msg.valid?
  end
end
