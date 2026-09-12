require "test_helper"

class ChatCompleterTest < ActiveSupport::TestCase
  class FakeXai
    def initialize(events: [], title: "Short title")
      @events = events
      @title = title
    end

    def stream_response(**)
      @events.each { |event| yield event }
    end

    def complete(**)
      {
        "output" => [ {
          "type" => "message",
          "content" => [ { "type" => "output_text", "text" => @title } ]
        } ]
      }
    end
  end

  setup do
    @user = User.create!(email: "you@x.com", password: "secret-ok")
    @chat = @user.conversations.create!
  end

  def text_events(*parts)
    parts.map { |text| { "type" => "response.output_text.delta", "delta" => text } } +
      [ { "type" => "response.completed", "response" => { "citations" => [] } } ]
  end

  test "plain turn writes a complete assistant and a title" do
    user = @chat.messages.create!(role: "user", content: "Hello there friend")
    assistant = @chat.messages.create!(role: "assistant", status: "pending", content: "")
    xai = FakeXai.new(events: text_events("Hi", "!"))
    ChatCompleter.new(assistant, xai: xai).run
    assistant.reload
    assert_equal "complete", assistant.status
    assert_equal "Hi!", assistant.content
    assert_equal "Short title", @chat.reload.title
    assert user
  end

  class BoomTitle < FakeXai
    def complete(**)
      raise Xai::Error, "nope"
    end
  end

  test "title request failure falls back to the first words" do
    @chat.messages.create!(role: "user", content: "Hello there friend")
    assistant = @chat.messages.create!(role: "assistant", status: "pending", content: "")
    xai = BoomTitle.new(events: text_events("Hi"))
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

    def stream_response(input:, tools: nil, reasoning_effort: nil, max_output_tokens: nil, prompt_cache_key: nil, **)
      @calls << {
        method: :stream_response,
        input: input,
        tools: tools,
        max_output_tokens: max_output_tokens,
        prompt_cache_key: prompt_cache_key
      }
      @reasoning_efforts << reasoning_effort
      @max_tokens_seen << max_output_tokens
      events = if tools.present?
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
        ]
      else
        [ { "type" => "response.output_text.delta", "delta" => "Hi" }, { "type" => "response.completed", "response" => {} } ]
      end
      events.each { |e| yield e }
    end

    def complete(prompt_cache_key: nil, **)
      @calls << { method: :complete, prompt_cache_key: prompt_cache_key }
      {
        "output" => [ {
          "type" => "message",
          "content" => [ { "type" => "output_text", "text" => "News" } ]
        } ]
      }
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
    call = xai.calls.find { |c| c[:method] == :stream_response }
    assert_equal [ { type: "web_search" } ], call[:tools]
    assert_nil call[:max_output_tokens]
    assert_equal "kura-#{@chat.id}", call[:prompt_cache_key]
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
    persona, turn_ctx = payload[0][:content], payload[1][:content]
    assert_match(/KuraChat/i, persona)
    refute_match(/live web search is available this turn/i, persona)
    refute_match(/Current date:/, persona)
    assert_match(/live web search is available this turn/i, turn_ctx)
    refute_match(/no live web this turn/i, turn_ctx)
    assert_match(/never invent urls/i, turn_ctx)
    assert_match(/Current date: \d{4}-\d{2}-\d{2}/, turn_ctx)
    assert_includes turn_ctx, "America/Sao_Paulo"
    assert_equal({ type: "web_search" }, ChatCompleter::WEB_SEARCH_TOOL)
  end

  test "plain turns keep low reasoning effort, omit tools, and omit max tokens" do
    @chat.messages.create!(role: "user", content: "Hi")
    assistant = @chat.messages.create!(role: "assistant", status: "pending", content: "")
    xai = RecordingXai.new
    ChatCompleter.new(assistant, xai: xai).run
    call = xai.calls.find { |c| c[:method] == :stream_response }
    assert_equal :stream_response, call[:method]
    assert_nil call[:tools]
    assert_equal "kura-#{@chat.id}", call[:prompt_cache_key]
    assert_equal %w[low], xai.reasoning_efforts
    assert_equal [ nil ], xai.max_tokens_seen
    persona, turn_ctx = call[:input][0][:content], call[:input][1][:content]
    refute_match(/live web/i, persona)
    assert_match(/no live web this turn/i, turn_ctx)
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
    xai = FakeXai.new(events: text_events(prose, mantra))
    ChatCompleter.new(assistant, xai: xai).run
    assistant.reload
    assert_equal "complete", assistant.status
    assert_includes assistant.content, "resumo objetivo"
    refute_match(/(Fim\.\n){4}/, assistant.content)
    assert_equal "truncated_repetition", assistant.error
  end

  test "short threads stay uncompacted so the prefix can grow" do
    18.times do |i|
      @chat.messages.create!(role: "user", content: "Question #{i} about taxes")
      @chat.messages.create!(role: "assistant", status: "complete", content: "Answer #{i} about taxes")
    end
    @chat.messages.create!(role: "user", content: "And now?")
    assistant = @chat.messages.create!(role: "assistant", status: "pending", content: "")
    xai = FakeXai.new(events: text_events("Later."), title: "Taxes")
    ChatCompleter.new(assistant, xai: xai).run
    @chat.reload
    assert_nil @chat.summary
    assert_nil @chat.summarized_through_id

    payload = ChatCompleter.new(assistant, xai: FakeXai.new).windowed_messages
    assert payload.any? { |m| m[:content].to_s.include?("Question 0 about taxes") }
    refute payload.any? { |m| m[:content].to_s.include?("Earlier conversation summary") }
  end

  test "compacts when the token window would overflow" do
    6.times do |i|
      @chat.messages.create!(role: "user", content: "Question #{i} about taxes")
      @chat.messages.create!(role: "assistant", status: "complete", content: "Answer #{i} about taxes")
    end
    user = @chat.messages.create!(role: "user", content: "And now?")
    assistant = @chat.messages.create!(role: "assistant", status: "pending", content: "")
    xai = FakeXai.new(
      events: text_events("Later."),
      title: "People discussed taxes and later asked a follow-up."
    )
    stub_const(ChatCompleter, :WINDOW_TOKENS, 80) do
      stub_const(ChatCompleter, :KEEP_RECENT_TOKENS, 30) do
        ChatCompleter.new(assistant, xai: xai).run
      end
    end
    @chat.reload
    assert_predicate @chat.summary, :present?
    assert @chat.summarized_through_id.present?
    assert @chat.summarized_through_id < user.id

    payload = ChatCompleter.new(assistant, xai: xai).windowed_messages
    assert_equal "system", payload[0][:role]
    assert_equal "system", payload[1][:role]
    assert_equal "system", payload[2][:role]
    assert_match(/Earlier conversation summary/, payload[2][:content])
    refute payload.any? { |m| m[:content].to_s.include?("Question 0 about taxes") }
  end

  test "window embeds attached images without costing the data-uri size" do
    user = @chat.messages.create!(role: "user", content: "Look")
    user.image.attach(
      io: File.open(Rails.root.join("test/fixtures/files/dot.png"), "rb"),
      filename: "dot.png",
      content_type: "image/png"
    )
    current = @chat.messages.create!(role: "assistant", status: "pending", content: "")
    payload = ChatCompleter.new(current).windowed_messages
    user_msg = payload.find { |m| m[:role] == "user" }
    parts = user_msg[:content]
    assert parts.is_a?(Array)
    assert parts.any? { |part| part[:type] == "input_image" && part[:image_url].to_s.start_with?("data:image/") }
    assert_operator user.input_cost, :<, 5_000
    assert_operator user.input_cost, :>=, Message::IMAGE_TOKENS
  end

  test "historical kagi tool rows are omitted from the model window" do
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
    refute payload.any? { |m| m[:role] == "tool" }
    refute payload.any? { |m| m[:tool_calls] }
    assert payload.any? { |m| m[:content] == "Found it." }
    assert early_user && later
  end

  test "completed response stores token usage and reasoning for replay" do
    @chat.messages.create!(role: "user", content: "Hi")
    assistant = @chat.messages.create!(role: "assistant", status: "pending", content: "")
    reasoning = { "type" => "reasoning", "encrypted_content" => "blob", "id" => "rs_1" }
    xai = FakeXai.new(events: [
      { "type" => "response.output_text.delta", "delta" => "Hi" },
      {
        "type" => "response.completed",
        "response" => {
          "output" => [ reasoning, { "type" => "message", "content" => [ { "type" => "output_text", "text" => "Hi" } ] } ],
          "usage" => {
            "input_tokens" => 120,
            "output_tokens" => 8,
            "input_tokens_details" => { "cached_tokens" => 90 },
            "output_tokens_details" => { "reasoning_tokens" => 12 }
          }
        }
      }
    ])
    ChatCompleter.new(assistant, xai: xai).run
    assistant.reload
    assert_equal(
      { "input_tokens" => 120, "cached_tokens" => 90, "output_tokens" => 8, "reasoning_tokens" => 12 },
      assistant.token_usage
    )
    assert_equal [ reasoning ], assistant.raw["reasoning"]
    replay = assistant.as_input
    assert_equal reasoning, replay.first
    assert_equal({ role: "assistant", content: "Hi" }, replay.last)
  end

  test "title and summary completes omit the conversation cache key" do
    @chat.messages.create!(role: "user", content: "Hello there friend")
    assistant = @chat.messages.create!(role: "assistant", status: "pending", content: "")
    xai = RecordingXai.new
    ChatCompleter.new(assistant, xai: xai).run
    completes = xai.calls.select { |c| c[:method] == :complete }
    assert_operator completes.size, :>=, 1
    completes.each { |c| assert_nil c[:prompt_cache_key] }
  end

  test "window replays reasoning ahead of the assistant text" do
    @chat.messages.create!(role: "user", content: "Hi")
    reasoning = { "type" => "reasoning", "encrypted_content" => "blob" }
    @chat.messages.create!(
      role: "assistant", status: "complete", content: "Hello",
      raw: { "reasoning" => [ reasoning ] }
    )
    user = @chat.messages.create!(role: "user", content: "Again")
    current = @chat.messages.create!(role: "assistant", status: "pending", content: "")
    payload = ChatCompleter.new(current).windowed_messages
    assert_equal reasoning, payload[-3]
    assert_equal({ role: "assistant", content: "Hello" }, payload[-2])
    assert_equal({ role: "user", content: "Again" }, payload[-1])
    assert user
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
