require "test_helper"

class BraveClientTest < ActiveSupport::TestCase
  setup do
    Brave::Client.reset!
  end

  teardown do
    Brave::Client.reset!
  end

  test "does not pin search language to the UI locale" do
    old_country = ENV["BRAVE_COUNTRY"]
    old_shared = ENV["SEARCH_REGION"]
    ENV.delete("BRAVE_COUNTRY")
    ENV.delete("SEARCH_REGION")
    I18n.with_locale(:pt) do
      payload = Brave::Client.build_payload(query: "Rails 8 release")
      refute payload.key?(:search_lang)
      assert_equal "BR", payload[:country]
      assert_equal 20, payload[:count]
      assert_equal 8_192, payload[:maximum_number_of_tokens]
      assert_equal 4_096, payload[:maximum_number_of_tokens_per_url]
      refute payload.key?(:enable_local)
      refute payload.key?(:enable_source_metadata)
    end
  ensure
    restore_env("BRAVE_COUNTRY", old_country)
    restore_env("SEARCH_REGION", old_shared)
  end

  test "omits country for English locale so tech queries stay global" do
    old_country = ENV["BRAVE_COUNTRY"]
    old_shared = ENV["SEARCH_REGION"]
    ENV.delete("BRAVE_COUNTRY")
    ENV.delete("SEARCH_REGION")
    I18n.with_locale(:en) do
      payload = Brave::Client.build_payload(query: "weather")
      refute payload.key?(:country)
    end
  ensure
    restore_env("BRAVE_COUNTRY", old_country)
    restore_env("SEARCH_REGION", old_shared)
  end

  test "uses an explicit region from the browser over the UI language" do
    I18n.with_locale(:en) do
      payload = Brave::Client.build_payload(query: "weather", region: "GB")
      assert_equal "GB", payload[:country]
    end
  end

  test "honors BRAVE_COUNTRY and BRAVE_SEARCH_LANG" do
    old_country = ENV["BRAVE_COUNTRY"]
    old_lang = ENV["BRAVE_SEARCH_LANG"]
    ENV["BRAVE_COUNTRY"] = "ALL"
    ENV["BRAVE_SEARCH_LANG"] = "pt"
    payload = Brave::Client.build_payload(query: "dólar")
    refute payload.key?(:country)
    assert_equal "pt", payload[:search_lang]
    web = Brave::Client.build_web_params(query: "dólar")
    refute web.key?(:country)
    assert_equal true, web[:extra_snippets]
  ensure
    restore_env("BRAVE_COUNTRY", old_country)
    restore_env("BRAVE_SEARCH_LANG", old_lang)
  end

  test "maps recency and truncates the query" do
    payload = Brave::Client.build_payload(query: "x" * 500, recency: "week")
    assert_equal "pw", payload[:freshness]
    assert payload[:q].length <= 400
  end

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
          "hostname" => "example.com",
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
    assert_equal "example.com", rows[0][:site]
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

  test "keeps more than eight grounding rows" do
    rows = Brave::Client.normalize({
      "grounding" => {
        "generic" => 12.times.map { |i|
          { "url" => "https://example.com/#{i}", "title" => "T#{i}", "snippets" => [ "s#{i}" ] }
        }
      }
    })
    assert_equal 12, rows.size
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

  test "maps web search news ahead of organic results" do
    rows = Brave::Client.normalize_web({
      "news" => {
        "results" => [
          {
            "title" => "Breaking",
            "url" => "https://news.example/a",
            "description" => "Dólar <strong>hoje</strong> a R$ 5,13",
            "page_age" => "2026-08-27T12:00:00",
            "meta_url" => { "hostname" => "news.example" }
          }
        ]
      },
      "web" => {
        "results" => [
          {
            "title" => "Docs",
            "url" => "https://docs.example",
            "description" => "Guide",
            "extra_snippets" => [ "More" ],
            "age" => "1 day ago"
          },
          { "title" => "Nope" }
        ]
      }
    })

    assert_equal [ "https://news.example/a", "https://docs.example" ], rows.map { |r| r[:url] }
    assert_equal "news.example", rows[0][:site]
    assert_equal "2026-08-27T12:00:00", rows[0][:date]
    assert_equal "Dólar hoje a R$ 5,13", rows[0][:snippet]
    refute_includes rows[0][:snippet], "<strong>"
    assert_includes rows[1][:snippet], "Guide"
    assert_includes rows[1][:snippet], "More"
  end

  test "falls back to web search when llm context is not in the plan" do
    client = FallbackClient.new
    rows = client.search(query: "dolar hoje")
    assert_equal "web", Brave::Client.endpoint
    refute Brave::Client.lean?
    assert_equal 1, rows.size
    assert_equal "https://wise.example", rows[0][:url]
    assert_equal %i[llm llm], client.posts
    assert_equal %i[full], client.gets
  end

  test "keeps llm context when the plan includes it" do
    client = FallbackClient.new
    client.llm_body = {
      "grounding" => {
        "generic" => [ { "url" => "https://docs.example", "title" => "Docs", "snippets" => [ "Rails 8" ] } ]
      }
    }
    rows = client.search(query: "Rails 8")
    assert_equal "llm", Brave::Client.endpoint
    assert_equal "https://docs.example", rows[0][:url]
    assert_equal %i[llm], client.posts
    assert_empty client.gets
  end

  test "retries llm without optional fields before giving up on the plan" do
    client = FallbackClient.new
    client.fail_llm_full = true
    client.llm_body = {
      "grounding" => {
        "generic" => [ { "url" => "https://lean.example", "title" => "Lean", "snippets" => [ "ok" ] } ]
      }
    }
    rows = client.search(query: "news")
    assert_equal "llm", Brave::Client.endpoint
    assert Brave::Client.lean?
    assert_equal "https://lean.example", rows[0][:url]
    assert_equal %i[llm llm], client.posts
    assert_empty client.gets
  end

  test "retries web search without extra snippets when those are plan-gated" do
    client = FallbackClient.new
    client.fail_web_full = true
    rows = client.search(query: "dolar hoje")
    assert_equal "web", Brave::Client.endpoint
    assert Brave::Client.lean?
    assert_equal "https://wise.example", rows[0][:url]
    assert_equal %i[full lean], client.gets
  end

  test "option_not_in_plan is detected from the Brave error code" do
    error = Brave::Error.new("http_400", http_status: 400, code: "OPTION_NOT_IN_PLAN")
    assert_predicate error, :option_not_in_plan?
    assert_predicate error, :plan_blocked?
    refute_predicate Brave::Error.new("http_429", http_status: 429, code: "RATE_LIMITED"), :plan_blocked?
  end

  test "missing key raises the same missing_key error the completer expects" do
    error = assert_raises(WebSearch::Error) { Brave::Client.new(api_key: "") }
    assert_equal "missing_key", error.message
  end

  class FallbackClient < Brave::Client
    attr_accessor :llm_body, :fail_llm_full, :fail_web_full
    attr_reader :posts, :gets

    def initialize
      @api_key = "x"
      @posts = []
      @gets = []
    end

    def post(_path, payload)
      lean = !payload.key?(:maximum_number_of_tokens)
      @posts << :llm
      raise_plan! if llm_body.nil? || (fail_llm_full && !lean)
      llm_body
    end

    def get(_path, params)
      lean = !params.key?(:extra_snippets)
      @gets << (lean ? :lean : :full)
      raise_plan! if fail_web_full && !lean
      {
        "web" => {
          "results" => [ { "title" => "Dólar", "url" => "https://wise.example", "description" => "5.40" } ]
        }
      }
    end

    def raise_plan!
      raise Brave::Error.new("http_400", http_status: 400, code: "OPTION_NOT_IN_PLAN")
    end
  end

  private
    def restore_env(name, old)
      if old
        ENV[name] = old
      else
        ENV.delete(name)
      end
    end
end
