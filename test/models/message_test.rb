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
    assert_equal([ { role: "user", content: "Hi" } ], user.as_input)

    assistant = @chat.messages.create!(role: "assistant", status: "complete", content: "Hello")
    assert_equal([ { role: "assistant", content: "Hello" } ], assistant.as_input)
  end

  test "as_input prepends stored reasoning items" do
    reasoning = { "type" => "reasoning", "encrypted_content" => "blob", "id" => "rs_1" }
    assistant = @chat.messages.create!(
      role: "assistant",
      status: "complete",
      content: "Hello",
      raw: { "reasoning" => [ reasoning ] }
    )
    assert_equal [ reasoning, { role: "assistant", content: "Hello" } ], assistant.as_input
  end

  test "as_input passes array content through" do
    user = @chat.messages.create!(role: "user", content: "Hi")
    user.define_singleton_method(:content) { [ { "type" => "input_text", "text" => "Hi" } ] }
    assert_equal(
      [ { role: "user", content: [ { "type" => "input_text", "text" => "Hi" } ] } ],
      user.as_input
    )
  end

  test "user content is capped" do
    msg = @chat.messages.new(role: "user", content: "x" * 16_385)
    assert_not msg.valid?
  end

  test "assistant content is not capped at 16384" do
    msg = @chat.messages.new(role: "assistant", status: "complete", content: "x" * 20_000)
    assert msg.valid?
  end

  test "image-only user message is valid and as_input embeds the image" do
    msg = @chat.messages.new(role: "user", content: "")
    attach_dot(msg)
    assert msg.valid?
    msg.save!
    payload = msg.as_input.sole
    parts = payload[:content]
    assert_equal "user", payload[:role]
    image = parts.find { |part| part[:type] == "input_image" }
    text = parts.find { |part| part[:type] == "input_text" }
    assert image[:image_url].start_with?("data:image/")
    assert_equal "high", image[:detail]
    assert_equal I18n.t("chat.image_prompt"), text[:text]
    assert_operator msg.input_cost, :>=, Message::IMAGE_TOKENS
  end

  test "captioned image keeps the caption" do
    msg = @chat.messages.new(role: "user", content: "What's this?")
    attach_dot(msg)
    msg.save!
    text = msg.as_input.sole[:content].find { |part| part[:type] == "input_text" }
    assert_equal "What's this?", text[:text]
  end

  test "rejects a non-image attachment" do
    msg = @chat.messages.new(role: "user", content: "Hi")
    msg.images.attach(io: StringIO.new("not an image"), filename: "x.txt", content_type: "text/plain")
    assert_not msg.valid?
    assert msg.errors[:images].any?
  end

  test "embeds up to four images and rejects a fifth" do
    msg = @chat.messages.new(role: "user", content: "Compare")
    4.times { attach_dot(msg) }
    assert msg.valid?, msg.errors.full_messages.to_sentence
    msg.save!
    parts = msg.as_input.sole[:content].select { |part| part[:type] == "input_image" }
    assert_equal 4, parts.size
    assert parts.all? { |part| part[:image_url].start_with?("data:image/") }

    msg.images.attach(
      io: File.open(Rails.root.join("test/fixtures/files/dot.png"), "rb"),
      filename: "fifth.png",
      content_type: "image/png"
    )
    assert_not msg.valid?
    assert msg.errors[:images].any?
  end

  test "image cost scales with the attachment count" do
    plain = @chat.messages.create!(role: "user", content: "Hi")
    msg = @chat.messages.new(role: "user", content: "Hi")
    3.times { attach_dot(msg) }
    msg.save!
    assert_equal plain.input_cost + Message::IMAGE_TOKENS * 3, msg.input_cost
  end

  test "deleting a conversation purges attached images from disk" do
    msg = @chat.messages.create!(role: "user", content: "pic")
    attach_dot(msg)
    attach_dot(msg)
    msg.save!
    ids_paths = msg.images.map { |image| [ image.blob.id, blob_path(image.blob) ] }
    assert ids_paths.all? { |_, path| File.exist?(path) }
    @chat.destroy
    ids_paths.each do |blob_id, path|
      assert_not File.exist?(path)
      assert_not ActiveStorage::Blob.exists?(blob_id)
    end
  end

  private
    def attach_dot(message)
      message.images.attach(
        io: File.open(Rails.root.join("test/fixtures/files/dot.png"), "rb"),
        filename: "dot.png",
        content_type: "image/png"
      )
    end

    def blob_path(blob)
      blob.service.path_for(blob.key)
    end
end
