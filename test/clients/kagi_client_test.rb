require "test_helper"

class KagiClientTest < ActiveSupport::TestCase
  test "does not pin a region when KAGI_REGION is ALL" do
    old = ENV["KAGI_REGION"]
    ENV["KAGI_REGION"] = "ALL"
    payload = Kagi::Client.build_payload(query: "dolar")
    refute payload.key?(:lens)
  ensure
    restore_env("KAGI_REGION", old)
  end

  test "localizes Portuguese UI to Brazil and keeps recency in the same lens" do
    old = ENV["KAGI_REGION"]
    ENV.delete("KAGI_REGION")
    I18n.with_locale(:pt) do
      payload = Kagi::Client.build_payload(query: "dolar hoje", recency: "day")
      assert_equal "BR", payload.dig(:lens, :search_region)
      assert_equal "day", payload.dig(:lens, :time_relative)
      assert_equal 3, payload.dig(:extract, :count)
    end
  ensure
    restore_env("KAGI_REGION", old)
  end

  test "omits extract when count is zero" do
    payload = Kagi::Client.build_payload(query: "news", extract_count: 0)
    refute payload.key?(:extract)
  end

  test "prefers news and weather over organic search and skips related queries" do
    rows = Kagi::Client.normalize({
      "data" => {
        "related_search" => [ { "title" => "query", "url" => "/search?q=x" } ],
        "search" => [
          { "title" => "Home", "url" => "https://g1.globo.com/", "snippet" => "Portal de notícias" }
        ],
        "news" => [
          { "title" => "Breaking", "url" => "https://g1.globo.com/politica/noticia.html", "snippet" => "Lula e Flávio", "time" => "2026-08-27T12:00:00Z", "props" => { "group_id" => "g1.globo.com" } }
        ],
        "weather" => [
          { "title" => "Curitiba", "url" => "https://www.climatempo.com.br/curitiba", "snippet" => "Amanhã 16 a 28C com sol.", "props" => { "group_id" => "climatempo.com.br" } }
        ]
      }
    })

    assert_equal [ "https://www.climatempo.com.br/curitiba", "https://g1.globo.com/politica/noticia.html" ], rows.map { |r| r[:url] }
    assert_equal "2026-08-27T12:00:00Z", rows[1][:date]
    assert_equal "g1.globo.com", rows[1][:site]
  end

  test "keeps one result per host using group_id" do
    rows = Kagi::Client.normalize({
      "search" => [
        { "title" => "A", "url" => "https://dolarhoje.com/", "snippet" => "Cotação comercial do dólar em R$ 5,14.", "props" => { "group_id" => "dolarhoje.com" } },
        { "title" => "B", "url" => "https://dolarhoje.com/ouro-hoje/", "snippet" => "Ouro também sobe.", "props" => { "group_id" => "dolarhoje.com" } },
        { "title" => "C", "url" => "https://economia.uol.com.br/cambio/", "snippet" => "Dólar comercial fecha a R$ 5,14.", "props" => { "group_id" => "economia.uol.com.br" } }
      ]
    })

    assert_equal [ "https://dolarhoje.com/", "https://economia.uol.com.br/cambio/" ], rows.map { |r| r[:url] }
  end

  test "drops cookie walls and share-button markdown from extracts" do
    rows = Kagi::Client.normalize({
      "search" => [
        {
          "title" => "Dólar Hoje",
          "url" => "https://dolarhoje.com/",
          "snippet" => "Usamos cookies e tecnologias semelhantes de acordo com a nossa Política de Privacidade. Ao continuar navegando, você concorda.",
          "props" => { "group_id" => "dolarhoje.com" }
        },
        {
          "title" => "Clima",
          "url" => "https://www.climatempo.com.br/amanha/curitiba-pr",
          "snippet" => "X [ ](https://www.facebook.com/sharer/sharer.php?u=https://climatempo.com.br)\n[ ](https://twitter.com/intent/tweet?text=oi)\nSol entre nuvens. Máxima 28°C em Curitiba amanhã.",
          "props" => { "group_id" => "climatempo.com.br" }
        }
      ]
    })

    assert_equal 1, rows.size
    assert_equal "https://www.climatempo.com.br/amanha/curitiba-pr", rows[0][:url]
    refute_includes rows[0][:snippet], "facebook.com"
    assert_includes rows[0][:snippet], "Máxima 28°C"
  end

  test "strips html and keeps the useful extract body" do
    body = "## 1. Upgrading to Rails 8.0\n\nIf you're upgrading an existing application, have good test coverage first." + (" more" * 80)
    rows = Kagi::Client.normalize({
      "search" => [
        {
          "title" => "Ruby on Rails 8.0 Release Notes",
          "url" => "https://guides.rubyonrails.org/8_0_release_notes.html",
          "snippet" => "Cotação de <strong>hoje</strong>\n#{body}",
          "time" => "2024-05-15T03:27:58Z"
        }
      ]
    })

    assert_equal 1, rows.size
    refute_includes rows[0][:snippet], "<strong>"
    assert_includes rows[0][:snippet], "Upgrading to Rails 8.0"
    assert_equal "guides.rubyonrails.org", rows[0][:site]
  end

  test "uses the page host when group_id is a path and unescapes titles" do
    rows = Kagi::Client.normalize({
      "search" => [
        {
          "title" => "What&#39;s new in Rails 8",
          "url" => "https://github.com/rails/rails/releases",
          "snippet" => "Rails 8.0.5 and 8.1.3 have been released.",
          "props" => { "group_id" => "/rails/rails" }
        }
      ]
    })

    assert_equal "What's new in Rails 8", rows[0][:title]
    assert_equal "github.com", rows[0][:site]
  end

  test "missing key raises the same missing_key error the completer expects" do
    error = assert_raises(WebSearch::Error) { Kagi::Client.new(api_key: "") }
    assert_equal "missing_key", error.message
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
