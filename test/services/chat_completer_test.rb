require "test_helper"

class ChatCompleterTest < ActiveSupport::TestCase
  class FakeXai
    def initialize(chunks: [], events: nil, title: "Short title")
      @chunks = chunks
      @events = events
      @title = title
    end

    def stream_chat(**)
      @chunks.each { |chunk| yield chunk }
    end

    def stream_response(**)
      (@events || []).each { |event| yield event }
    end

    def chat(**)
      { "choices" => [ { "message" => { "content" => @title } } ] }
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
    attr_reader :calls, :reasoning_efforts, :max_tokens_seen

    def initialize
      @calls = []
      @reasoning_efforts = []
      @max_tokens_seen = []
    end

    def stream_chat(reasoning_effort: nil, max_tokens: nil, **)
      @calls << :stream_chat
      @reasoning_efforts << reasoning_effort
      @max_tokens_seen << max_tokens
      [ { "choices" => [ { "delta" => { "content" => "Hi" }, "finish_reason" => "stop" } ] } ].each { |c| yield c }
    end

    def stream_response(input:, tools:, store: false, reasoning_effort: nil, max_output_tokens: nil, **)
      @calls << { method: :stream_response, input: input, tools: tools, store: store, max_output_tokens: max_output_tokens }
      @reasoning_efforts << reasoning_effort
      @max_tokens_seen << max_output_tokens
      [
        { "type" => "response.web_search_call.in_progress" },
        { "type" => "response.output_text.delta", "delta" => "Here." },
        {
          "type" => "response.completed",
          "response" => {
            "citations" => [ "https://example.com/news" ],
            "output" => [ {
              "type" => "message",
              "content" => [ {
                "type" => "output_text",
                "text" => "Here.",
                "annotations" => [ { "type" => "url_citation", "url" => "https://example.com/news", "title" => "1" } ]
              } ]
            } ]
          }
        }
      ].each { |e| yield e }
    end

    def chat(**)
      { "choices" => [ { "message" => { "content" => "News" } } ] }
    end
  end

  test "web turn uses Responses web_search and stores citations" do
    @chat.messages.create!(role: "user", content: "News?", web: true)
    assistant = @chat.messages.create!(role: "assistant", status: "pending", content: "")

    xai = RecordingXai.new
    ChatCompleter.new(assistant, xai: xai).run
    assistant.reload
    assert_equal "complete", assistant.status
    assert_equal "Here.", assistant.content
    assert_equal 0, @chat.messages.where(role: "tool").count
    refute @chat.messages.reload.any?(&:tool_calls?)
    assert_equal [ { "title" => "example.com", "url" => "https://example.com/news" } ], assistant.citations
    call = xai.calls.find { |c| c.is_a?(Hash) && c[:method] == :stream_response }
    assert_equal [ { type: "web_search" } ], call[:tools]
    assert_nil call[:max_output_tokens]
    assert_equal %w[medium], xai.reasoning_efforts
    roles = call[:input].map { |m| m[:role] }
    assert_includes roles, "system"
    assert_includes roles, "user"
    refute_includes roles, "tool"
  end

  test "web turn system prompt offers search without requiring a tool call" do
    @chat.messages.create!(role: "user", content: "News?", web: true)
    assistant = @chat.messages.create!(role: "assistant", status: "pending", content: "")
    payload = ChatCompleter.new(assistant, xai: FakeXai.new).windowed_messages
    system = payload.first[:content]
    assert_match(/live web search this turn/i, system)
    refute_match(/Call web_search before answering/i, system)
    refute_match(/no live web access/i, system)
    assert_match(/Current date: \d{4}-\d{2}-\d{2}/, system)
    assert_includes system, "America/Sao_Paulo"
    assert_equal({ type: "web_search" }, ChatCompleter::WEB_SEARCH_TOOL)
  end

  test "plain turns keep low reasoning effort and omit max_tokens" do
    @chat.messages.create!(role: "user", content: "Hi")
    assistant = @chat.messages.create!(role: "assistant", status: "pending", content: "")
    xai = RecordingXai.new
    ChatCompleter.new(assistant, xai: xai).run
    assert_equal [ :stream_chat ], xai.calls
    assert_equal %w[low], xai.reasoning_efforts
    assert_equal [ nil ], xai.max_tokens_seen
  end

  test "aborts citation-token loops and keeps the useful prose" do
    pua = "\uE000"
    prose = "Não existe garantia absoluta, mas dá para reduzir risco."
    junk = 20.times.map { |i|
      "#{pua}markdown:#{i + 1}#{pua}#{pua}l#{pua}https://example.com/a#{pua}#{pua}r#{pua}Fonte#{pua}"
    }.join
    @chat.messages.create!(role: "user", content: "Seguro?", web: true)
    assistant = @chat.messages.create!(role: "assistant", status: "pending", content: "")
    xai = FakeXai.new(events: [
      { "type" => "response.output_text.delta", "delta" => prose },
      { "type" => "response.output_text.delta", "delta" => junk },
      { "type" => "response.completed", "response" => { "citations" => [] } }
    ])
    ChatCompleter.new(assistant, xai: xai).run
    assistant.reload
    assert_equal "complete", assistant.status
    assert_equal prose, assistant.content
    assert_equal "truncated_repetition", assistant.error
    assert_operator assistant.content.length, :<, 500
  end

  test "aborts closing mantra loops" do
    prose = "Segue o resumo objetivo do que importa.\n\n"
    mantra = ([ "Fim.\n", "Resposta.\n", "Resumo.\n" ] * 10).join
    @chat.messages.create!(role: "user", content: "Resume")
    assistant = @chat.messages.create!(role: "assistant", status: "pending", content: "")
    xai = FakeXai.new(chunks: [
      { "choices" => [ { "delta" => { "content" => prose } } ] },
      { "choices" => [ { "delta" => { "content" => mantra }, "finish_reason" => "length" } ] }
    ])
    ChatCompleter.new(assistant, xai: xai).run
    assistant.reload
    assert_equal "complete", assistant.status
    assert_includes assistant.content, "resumo objetivo"
    refute_match(/(Fim\.\n){4}/, assistant.content)
    assert_equal "truncated_repetition", assistant.error
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
    completer = ChatCompleter.new(current)
    payload = completer.windowed_messages
    tool = payload.find { |m| m[:role] == "tool" }
    assert tool
    parsed = JSON.parse(tool[:content])
    assert_equal "A", parsed["results"][0]["title"]
    assert_nil parsed["results"][0]["snippet"]
    input = completer.response_input(payload)
    refute input.any? { |m| m[:role] == "tool" }
    refute input.any? { |m| m[:tool_calls] }
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

  test "citations_from dedupes urls from citations and annotations" do
    rows = ChatCompleter.citations_from(
      "citations" => [ "https://a.example", "https://a.example" ],
      "output" => [ {
        "content" => [ {
          "annotations" => [
            { "url" => "https://a.example", "title" => "1" },
            { "url" => "https://b.example", "title" => "News" }
          ]
        } ]
      } ]
    )
    assert_equal [
      { "title" => "a.example", "url" => "https://a.example" },
      { "title" => "News", "url" => "https://b.example" }
    ], rows
  end
end
