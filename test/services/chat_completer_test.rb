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

  class BoomTitle < FakeXai
    def chat(**)
      raise Xai::Error, "nope"
    end
  end

  test "title request failure falls back to the first words" do
    @chat.messages.create!(role: "user", content: "Hello there friend")
    assistant = @chat.messages.create!(role: "assistant", status: "pending", content: "")
    xai = BoomTitle.new(chunks: [
      { "choices" => [ { "delta" => { "content" => "Hi" }, "finish_reason" => "stop" } ] }
    ])
    ChatCompleter.new(assistant, xai: xai).run
    assistant.reload
    assert_equal "complete", assistant.status
    assert_equal "Hello there friend", @chat.reload.title
  end

  class RecordingXai
    attr_reader :tool_choices

    def initialize
      @tool_choices = []
      @n = 0
    end

    def stream_chat(tool_choice: nil, **)
      @tool_choices << tool_choice
      @n += 1
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

    def chat(**)
      { "choices" => [ { "message" => { "content" => "News" } } ] }
    end
  end

  test "web turn persists hidden tool rows and a legal window" do
    @chat.messages.create!(role: "user", content: "News?", web: true)
    assistant = @chat.messages.create!(role: "assistant", status: "pending", content: "")

    xai = RecordingXai.new
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
    assert_equal %w[required auto], xai.tool_choices
  end

  test "web turn system prompt tells the model to search" do
    @chat.messages.create!(role: "user", content: "News?", web: true)
    assistant = @chat.messages.create!(role: "assistant", status: "pending", content: "")
    payload = ChatCompleter.new(assistant, xai: FakeXai.new(chunks: [])).windowed_messages
    assert_match(/live web access this turn/i, payload.first[:content])
    refute_match(/no live web access/i, payload.first[:content])
    refute_match(/Do not search for general knowledge/i, ChatCompleter::WEB_SEARCH_TOOL.dig(:function, :description))
  end

  test "compacts older turns into a stored summary" do
    18.times do |i|
      @chat.messages.create!(role: "user", content: "Question #{i} about taxes")
      @chat.messages.create!(role: "assistant", status: "complete", content: "Answer #{i} about taxes")
    end
    user = @chat.messages.create!(role: "user", content: "And now?")
    assistant = @chat.messages.create!(role: "assistant", status: "pending", content: "")
    xai = FakeXai.new(
      chunks: [ { "choices" => [ { "delta" => { "content" => "Later." }, "finish_reason" => "stop" } ] } ],
      title: "People discussed taxes and later asked a follow-up."
    )
    ChatCompleter.new(assistant, xai: xai).run
    @chat.reload
    assert_predicate @chat.summary, :present?
    assert @chat.summarized_through_id.present?
    assert @chat.summarized_through_id < user.id

    payload = ChatCompleter.new(assistant, xai: xai).windowed_messages
    system = payload.first[:content]
    assert_match(/Earlier conversation summary/, system)
    refute payload.any? { |m| m[:content].to_s.include?("Question 0 about taxes") }
  end

  test "historical tool extracts are stripped for later turns" do
    early_user = @chat.messages.create!(role: "user", content: "search", web: true)
    @chat.messages.create!(
      role: "assistant", status: "complete", content: nil,
      raw: { "tool_calls" => [ { "id" => "c1", "type" => "function", "function" => { "name" => "web_search", "arguments" => "{}" } } ] }
    )
    fat = { "query" => "news", "results" => [ { "title" => "A", "url" => "https://a.example", "snippet" => "x" * 1500 } ] }.to_json
    @chat.messages.create!(role: "tool", content: fat, raw: { "tool_call_id" => "c1" })
    @chat.messages.create!(role: "assistant", status: "complete", content: "Found it.")
    later = @chat.messages.create!(role: "user", content: "thanks")
    current = @chat.messages.create!(role: "assistant", status: "pending", content: "")
    payload = ChatCompleter.new(current).windowed_messages
    tool = payload.find { |m| m[:role] == "tool" }
    assert tool
    parsed = JSON.parse(tool[:content])
    assert_equal "A", parsed["results"][0]["title"]
    assert_nil parsed["results"][0]["snippet"]
    assert early_user && later
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
