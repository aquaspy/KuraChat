require "test_helper"

class ChatCompleterTest < ActiveSupport::TestCase
  class FakeXai
    def initialize(chunks:, title: "Short title")
      @chunks = chunks
      @title = title
    end

    def stream_chat(**)
      @chunks.each { |chunk| yield chunk }
    end

    def chat(**)
      { "choices" => [ { "message" => { "content" => @title } } ] }
    end
  end

  class FakeKagi
    def search(**)
      [ { title: "Kagi", url: "https://kagi.com", date: "", snippet: "Search" } ]
    end
  end

  setup do
    @user = User.create!(email: "you@x.com", password: "secret-ok")
    @chat = @user.conversations.create!
  end

  test "plain turn writes a complete assistant and a title" do
    user = @chat.messages.create!(role: "user", content: "Hello there friend")
    assistant = @chat.messages.create!(role: "assistant", status: "pending", content: "")
    xai = FakeXai.new(chunks: [
      { "choices" => [ { "delta" => { "content" => "Hi" } } ] },
      { "choices" => [ { "delta" => { "content" => "!" }, "finish_reason" => "stop" } ] }
    ])
    ChatCompleter.new(assistant, xai: xai).run
    assistant.reload
    assert_equal "complete", assistant.status
    assert_equal "Hi!", assistant.content
    assert_equal "Short title", @chat.reload.title
    assert user
  end

  test "web turn persists hidden tool rows and a legal window" do
    @chat.messages.create!(role: "user", content: "News?", web: true)
    assistant = @chat.messages.create!(role: "assistant", status: "pending", content: "")

    xai = Object.new
    def xai.stream_chat(**)
      @n = (@n || 0) + 1
      chunks = if @n == 1
        [ { "choices" => [ { "delta" => { "tool_calls" => [ {
          "index" => 0, "id" => "call_1", "type" => "function",
          "function" => { "name" => "web_search", "arguments" => "{\"query\":\"news\"}" }
        } ] }, "finish_reason" => "tool_calls" } ] } ]
      else
        [ { "choices" => [ { "delta" => { "content" => "Here." }, "finish_reason" => "stop" } ] } ]
      end
      chunks.each { |c| yield c }
    end
    def xai.chat(**)
      { "choices" => [ { "message" => { "content" => "News" } } ] }
    end

    ChatCompleter.new(assistant, xai: xai, kagi: FakeKagi.new).run
    assistant.reload
    assert_equal "complete", assistant.status
    assert_equal "Here.", assistant.content
    assert_equal 1, @chat.messages.where(role: "tool").count
    hidden = @chat.messages.reload.find(&:tool_calls?)
    assert_equal "complete", hidden.status

    payload = ChatCompleter.new(assistant, xai: xai).windowed_messages
    roles = payload.map { |m| m[:role] || m["role"] }
    assert_includes roles, "system"
    assert_includes roles, "tool"
    assert payload.any? { |m| m[:tool_calls] }
    refute payload.any? { |m| m[:role] == "assistant" && m[:content] == "" && m[:tool_calls].blank? }
  end

  test "window drops a split tool group" do
    @chat.messages.create!(role: "user", content: "a")
    @chat.messages.create!(
      role: "assistant", status: "complete", content: nil,
      raw: { "tool_calls" => [ { "id" => "x", "type" => "function", "function" => { "name" => "web_search", "arguments" => "{}" } } ] }
    )
    # missing matching tool row
    current = @chat.messages.create!(role: "assistant", status: "pending", content: "")
    payload = ChatCompleter.new(current).windowed_messages
    refute payload.any? { |m| m[:tool_calls] }
    refute payload.any? { |m| m[:role] == "tool" }
  end
end
