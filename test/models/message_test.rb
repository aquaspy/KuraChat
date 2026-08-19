require "test_helper"

class MessageTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "you@x.com", password: "secret-ok")
    @chat = @user.conversations.create!
  end

  test "as_openai drops placeholders and blank tool-less assistants" do
    pending = @chat.messages.create!(role: "assistant", status: "pending", content: "")
    assert_nil pending.as_openai

    hidden = @chat.messages.create!(
      role: "assistant",
      status: "complete",
      content: nil,
      raw: { "tool_calls" => [ { "id" => "c1", "type" => "function", "function" => { "name" => "web_search", "arguments" => "{}" } } ] }
    )
    payload = hidden.as_openai
    assert_equal "assistant", payload[:role]
    assert_nil payload[:content]
    assert payload[:tool_calls]

    tool = @chat.messages.create!(role: "tool", content: "{}", raw: { "tool_call_id" => "c1" })
    assert_equal "c1", tool.as_openai[:tool_call_id]
  end

  test "user content is capped" do
    msg = @chat.messages.new(role: "user", content: "x" * 16_385)
    assert_not msg.valid?
  end

  test "assistant content is not capped at 16384" do
    msg = @chat.messages.new(role: "assistant", status: "complete", content: "x" * 20_000)
    assert msg.valid?
  end

  test "compact_tool_json keeps titles and drops extracts" do
    json = {
      "query" => "rails",
      "results" => [ { "title" => "Docs", "url" => "https://rubyonrails.org", "snippet" => "x" * 1800 } ]
    }.to_json
    compact = Message.compact_tool_json(json)
    parsed = JSON.parse(compact)
    assert_equal "rails", parsed["query"]
    assert_equal "Docs", parsed["results"][0]["title"]
    assert_nil parsed["results"][0]["snippet"]
  end
end
