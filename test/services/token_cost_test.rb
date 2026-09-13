require "test_helper"

class TokenCostTest < ActiveSupport::TestCase
  test "usd_for uses short-context grok-4.3 list prices" do
    usage = { "input_tokens" => 100_000, "cached_tokens" => 0, "output_tokens" => 100_000, "reasoning_tokens" => 0 }
    assert_in_delta 0.375, TokenCost.usd_for(usage), 0.0001
  end

  test "cached tokens are billed at the cache rate" do
    usage = { "input_tokens" => 100_000, "cached_tokens" => 100_000, "output_tokens" => 0, "reasoning_tokens" => 0 }
    assert_in_delta 0.02, TokenCost.usd_for(usage), 0.0001
  end

  test "reasoning tokens are billed as output" do
    usage = { "input_tokens" => 0, "output_tokens" => 8, "reasoning_tokens" => 12 }
    expected = (8 + 12) * 2.50 / 1_000_000.0
    assert_in_delta expected, TokenCost.usd_for(usage), 0.0000001
  end

  test "long-context rates apply when input reaches the threshold" do
    usage = { "input_tokens" => 200_000, "cached_tokens" => 0, "output_tokens" => 0 }
    assert_in_delta 0.50, TokenCost.usd_for(usage), 0.0001
  end

  test "uses grok-4.6 list prices when that model is stored" do
    usage = { "model" => "grok-4.6", "input_tokens" => 100_000, "output_tokens" => 100_000, "reasoning_tokens" => 0 }
    assert_in_delta 0.80, TokenCost.usd_for(usage), 0.0001
  end

  test "prefers billed ticks over the list-price estimate" do
    usage = {
      "input_tokens" => 100_000,
      "output_tokens" => 100_000,
      "cost_in_usd_ticks" => 37_756_000
    }
    assert_in_delta 0.0037756, TokenCost.usd_for(usage), 0.0000001
  end

  test "fallback adds counted web_search calls at 5 dollars per thousand" do
    tokens = { "input_tokens" => 0, "output_tokens" => 0, "web_search_calls" => 2 }
    assert_in_delta 0.01, TokenCost.usd_for(tokens), 0.0000001
  end

  test "billed ticks already include web search so calls are not added again" do
    usage = { "cost_in_usd_ticks" => 50_000_000, "web_search_calls" => 3, "input_tokens" => 10 }
    assert_in_delta 0.005, TokenCost.usd_for(usage), 0.0000001
  end

  test "format hides zero and uses extra decimals under a cent" do
    assert_nil TokenCost.format_usd(0)
    assert_equal "$0.0042", TokenCost.format_usd(0.0042)
    assert_equal "$0.123", TokenCost.format_usd(0.1234)
    assert_equal "$1.23", TokenCost.format_usd(1.234)
  end

  test "conversation sums usage across assistant turns" do
    user = User.create!(email: "cost@x.com", password: "secret-ok")
    chat = user.conversations.create!
    chat.messages.create!(role: "user", content: "hi")
    chat.messages.create!(
      role: "assistant", status: "complete", content: "yo",
      token_usage: { "input_tokens" => 1000, "cached_tokens" => 0, "output_tokens" => 400, "reasoning_tokens" => 100 }
    )
    chat.messages.create!(
      role: "assistant", status: "complete", content: "again",
      token_usage: { "input_tokens" => 2000, "cached_tokens" => 500, "output_tokens" => 200, "reasoning_tokens" => 0 }
    )
    expected = TokenCost.usd_for_many(chat.token_usages)
    assert_operator expected, :>, 0
    assert_in_delta expected, chat.estimated_api_cost, 0.0000001
    assert_match(/\$0\.\d+/, TokenCost.format_usd(expected))
  end
end
