require "test_helper"

class BraveClientTest < ActiveSupport::TestCase
  test "maps web results including extra snippets" do
    rows = Brave::Client.normalize({
      "web" => {
        "results" => [
          {
            "title" => "Hello",
            "url" => "https://example.com/a",
            "description" => "World",
            "age" => "2024-01-01T00:00:00Z",
            "extra_snippets" => [ "More context" ]
          },
          {
            "title" => "Second",
            "url" => "https://example.com/b",
            "description" => "Only desc",
            "page_age" => "2023-12-01"
          }
        ]
      }
    })

    assert_equal 2, rows.size
    assert_equal "Hello", rows[0][:title]
    assert_equal "https://example.com/a", rows[0][:url]
    assert_equal "2024-01-01T00:00:00Z", rows[0][:date]
    assert_includes rows[0][:snippet], "World"
    assert_includes rows[0][:snippet], "More context"
    assert_equal "Only desc", rows[1][:snippet]
    assert_equal "2023-12-01", rows[1][:date]
  end

  test "maps recency to brave freshness values" do
    assert_equal "pd", Brave::Client::FRESHNESS["day"]
    assert_equal "pw", Brave::Client::FRESHNESS["week"]
    assert_equal "pm", Brave::Client::FRESHNESS["month"]
    assert_nil Brave::Client::FRESHNESS["any"]
  end

  test "missing key raises the same missing_key error the completer expects" do
    error = assert_raises(WebSearch::Error) { Brave::Client.new(api_key: "") }
    assert_equal "missing_key", error.message
  end
end
