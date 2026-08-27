require "test_helper"

class WebSearchTest < ActiveSupport::TestCase
  test "defaults to kagi" do
    old = ENV["WEB_SEARCH_PROVIDER"]
    ENV.delete("WEB_SEARCH_PROVIDER")
    assert_equal "kagi", WebSearch.provider
  ensure
    restore_env("WEB_SEARCH_PROVIDER", old)
  end

  test "accepts brave as the provider" do
    old = ENV["WEB_SEARCH_PROVIDER"]
    ENV["WEB_SEARCH_PROVIDER"] = "brave"
    assert_equal "brave", WebSearch.provider
  ensure
    restore_env("WEB_SEARCH_PROVIDER", old)
  end

  test "unknown provider falls back to kagi" do
    old = ENV["WEB_SEARCH_PROVIDER"]
    ENV["WEB_SEARCH_PROVIDER"] = "bing"
    assert_equal "kagi", WebSearch.provider
  ensure
    restore_env("WEB_SEARCH_PROVIDER", old)
  end

  test "builds a brave client" do
    old_provider = ENV["WEB_SEARCH_PROVIDER"]
    old_key = ENV["BRAVE_API_KEY"]
    ENV["WEB_SEARCH_PROVIDER"] = "brave"
    ENV["BRAVE_API_KEY"] = "x"
    assert_instance_of Brave::Client, WebSearch.client
  ensure
    restore_env("WEB_SEARCH_PROVIDER", old_provider)
    restore_env("BRAVE_API_KEY", old_key)
  end

  test "reads the region from Accept-Language and defaults Portuguese to BR" do
    assert_equal "BR", WebSearch.region_from_header("pt-BR,pt;q=0.9,en;q=0.8")
    assert_equal "PT", WebSearch.region_from_header("pt-PT,pt;q=0.9")
    assert_equal "GB", WebSearch.region_from_header("en-GB,en;q=0.8")
    assert_equal "US", WebSearch.region_from_header("en-US,en;q=0.9")
    assert_equal "BR", WebSearch.region_from_header("pt,en-US;q=0.8")
    assert_nil WebSearch.region_from_header("en")
    assert_nil WebSearch.normalize_region("ALL")
    assert_equal "BR", WebSearch.region_from_locale(:pt)
    assert_nil WebSearch.region_from_locale(:en)
    assert_nil WebSearch.region(explicit: "ALL", locale: :pt)
    assert_equal "PT", WebSearch.region(explicit: "PT", locale: :pt)
  end

  test "builds a kagi client" do
    old_provider = ENV["WEB_SEARCH_PROVIDER"]
    old_key = ENV["KAGI_API_KEY"]
    ENV["WEB_SEARCH_PROVIDER"] = "kagi"
    ENV["KAGI_API_KEY"] = "x"
    assert_instance_of Kagi::Client, WebSearch.client
  ensure
    restore_env("WEB_SEARCH_PROVIDER", old_provider)
    restore_env("KAGI_API_KEY", old_key)
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
