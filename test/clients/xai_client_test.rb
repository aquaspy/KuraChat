require "test_helper"

class XaiClientTest < ActiveSupport::TestCase
  class CaptureClient < Xai::Client
    attr_reader :path, :payload

    def post_sse(path, body)
      @path = path
      @payload = body
    end

    def post_json(path, body)
      @path = path
      @payload = body
      { "output" => [] }
    end
  end

  setup do
    @client = CaptureClient.new(api_key: "x", model: "grok-4.3")
  end

  test "stream_response is store false and omits tools unless given" do
    @client.stream_response(input: [ { role: "user", content: "Hi" } ], reasoning_effort: "low")
    assert_equal "/responses", @client.path
    assert_equal false, @client.payload[:store]
    assert @client.payload[:stream]
    assert_equal [ "no_inline_citations" ], @client.payload[:include]
    refute @client.payload.key?(:tools)
    refute @client.payload.key?(:max_output_tokens)
    assert_equal "low", @client.payload[:reasoning_effort]
  end

  test "stream_response includes web_search when asked" do
    @client.stream_response(
      input: [ { role: "user", content: "News?" } ],
      tools: [ { type: "web_search" } ],
      reasoning_effort: "medium"
    )
    assert_equal [ { type: "web_search" } ], @client.payload[:tools]
    assert_equal false, @client.payload[:store]
  end

  test "complete is a non-stream Responses call" do
    @client.complete(input: [ { role: "user", content: "Title me" } ], max_output_tokens: 24)
    assert_equal "/responses", @client.path
    assert_equal false, @client.payload[:stream]
    assert_equal false, @client.payload[:store]
    refute @client.payload.key?(:include)
    assert_equal 24, @client.payload[:max_output_tokens]
  end

  test "output_text joins message content" do
    text = Xai::Client.output_text(
      "output" => [
        { "type" => "reasoning", "content" => [] },
        { "type" => "message", "content" => [ { "type" => "output_text", "text" => "Hi" }, { "type" => "output_text", "text" => "!" } ] }
      ]
    )
    assert_equal "Hi!", text
  end

  test "missing key raises" do
    error = assert_raises(Xai::Error) { Xai::Client.new(api_key: "") }
    assert_equal "missing_key", error.message
  end
end
