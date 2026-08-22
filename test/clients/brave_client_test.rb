require "test_helper"

class BraveClientTest < ActiveSupport::TestCase
  test "maps llm context grounding including source dates" do
    rows = Brave::Client.normalize({
      "grounding" => {
        "generic" => [
          {
            "url" => "https://example.com/a",
            "title" => "Hello",
            "snippets" => [ "World", "More context" ]
          },
          {
            "url" => "https://example.com/b",
            "title" => "Second",
            "snippets" => []
          }
        ]
      },
      "sources" => {
        "https://example.com/a" => {
          "title" => "Hello",
          "age" => [ "Monday, January 1, 2024", "2024-01-01", "2 years ago", "2024-01-01T00:00:00Z" ]
        },
        "https://example.com/b" => {
          "title" => "Second",
          "description" => "Only desc",
          "age" => [ "December 1, 2023", "2023-12-01" ]
        }
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

  test "includes poi and map rows when present" do
    rows = Brave::Client.normalize({
      "grounding" => {
        "generic" => [],
        "poi" => {
          "url" => "https://cafe.example",
          "title" => "Cafe",
          "snippets" => [ "Coffee" ]
        },
        "map" => [
          { "url" => "https://park.example", "title" => "Park", "snippets" => [ "Grass" ] }
        ]
      },
      "sources" => {}
    })

    assert_equal [ "https://cafe.example", "https://park.example" ], rows.map { |r| r[:url] }
    assert_equal "Coffee", rows[0][:snippet]
  end

  test "serializes structured snippets as json" do
    rows = Brave::Client.normalize({
      "grounding" => {
        "generic" => [
          {
            "url" => "https://example.com/table",
            "title" => "Stats",
            "snippets" => [ "Intro", { "rows" => [ 1, 2 ] } ]
          }
        ]
      }
    })

    assert_includes rows[0][:snippet], "Intro"
    assert_includes rows[0][:snippet], "{\"rows\":[1,2]}"
  end

  test "skips rows without a url" do
    rows = Brave::Client.normalize({
      "grounding" => {
        "generic" => [
          { "title" => "Nope", "snippets" => [ "x" ] },
          { "url" => "https://ok.example", "title" => "Ok", "snippets" => [ "y" ] }
        ]
      }
    })

    assert_equal 1, rows.size
    assert_equal "https://ok.example", rows[0][:url]
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
