require "test_helper"

class XaiClientTest < ActiveSupport::TestCase
  class CaptureClient < Xai::Client
    attr_reader :path, :payload

    def post_sse(path, body)
      @path = path
      @payload = body
    end
  end

  setup do
    @client = CaptureClient.new(api_key: "x", model: "grok-4.3")
  end

  test "stream_chat omits max_tokens unless given" do
    @client.stream_chat(messages: [ { role: "user", content: "Hi" } ], reasoning_effort: "low")
    assert_equal "/chat/completions", @client.path
    refute @client.payload.key?(:max_tokens)
    refute @client.payload.key?(:tools)
    assert_equal "low", @client.payload[:reasoning_effort]
  end

  test "stream_response uses web_search, store false, no output cap" do
    @client.stream_response(
      input: [ { role: "user", content: "News?" } ],
      tools: [ { type: "web_search" } ],
      reasoning_effort: "medium"
    )
    assert_equal "/responses", @client.path
    assert_equal false, @client.payload[:store]
    assert_equal [ { type: "web_search" } ], @client.payload[:tools]
    refute @client.payload.key?(:max_output_tokens)
    assert @client.payload[:stream]
  end

  test "missing key raises" do
    error = assert_raises(Xai::Error) { Xai::Client.new(api_key: "") }
    assert_equal "missing_key", error.message
  end
end
