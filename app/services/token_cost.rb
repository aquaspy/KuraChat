# Converts stored xAI usage into USD.
#
# Prefer the API's cost_in_usd_ticks (actual billed amount: model, cache,
# reasoning, and server-side tools such as web_search). Fall back to the
# public list for that model plus $5 / 1k web_search calls only when ticks
# are missing (older rows). Do not invent a web-search count.
class TokenCost
  PER_MILLION = 1_000_000.0
  TICKS_PER_USD = 10_000_000_000.0
  LONG_AT = 200_000
  WEB_SEARCH_PER_CALL = 5.0 / 1_000.0

  # Public xAI Text API rates (USD / 1M tokens), short then long context.
  RATES = {
    "grok-4.6" => {
      short: { input: 2.00, cached: 0.50, output: 6.00 },
      long:  { input: 4.00, cached: 1.00, output: 12.00 }
    },
    "grok-4.5" => {
      short: { input: 2.00, cached: 0.30, output: 6.00 },
      long:  { input: 4.00, cached: 0.60, output: 12.00 }
    },
    "grok-4.3" => {
      short: { input: 1.25, cached: 0.20, output: 2.50 },
      long:  { input: 2.50, cached: 0.40, output: 5.00 }
    },
    "grok-4.20" => {
      short: { input: 1.25, cached: 0.20, output: 2.50 },
      long:  { input: 2.50, cached: 0.40, output: 5.00 }
    },
    "grok-build-0.1" => {
      short: { input: 1.00, cached: 0.20, output: 2.00 },
      long:  { input: 2.00, cached: 0.40, output: 4.00 }
    }
  }.freeze
  RATE_KEYS = %w[grok-4.6 grok-4.5 grok-build-0.1 grok-4.20 grok-4.3].freeze

  def self.usd_for(usage)
    return 0.0 if usage.blank?

    row = normalize(usage)
    return ticks_to_usd(row["cost_in_usd_ticks"]) if billed?(row)

    input = row["input_tokens"].to_i
    cached = [ row["cached_tokens"].to_i, input ].min
    uncached = input - cached
    billed_out = row["output_tokens"].to_i + row["reasoning_tokens"].to_i
    rates = rates_for(row["model"], input)
    tokens = (uncached * rates[:input] + cached * rates[:cached] + billed_out * rates[:output]) / PER_MILLION
    tokens + row["web_search_calls"].to_i * WEB_SEARCH_PER_CALL
  end

  def self.usd_for_many(usages)
    Array(usages).sum { |u| usd_for(u) }
  end

  def self.billed?(usage)
    return false if usage.blank?

    row = normalize(usage)
    row.key?("cost_in_usd_ticks") && !row["cost_in_usd_ticks"].nil?
  end

  def self.format_usd(usd)
    return nil if usd.nil? || usd <= 0
    return Kernel.format("$%.4f", usd) if usd < 0.01
    return Kernel.format("$%.3f", usd) if usd < 1

    Kernel.format("$%.2f", usd)
  end

  def self.normalize(usage)
    row = usage.respond_to?(:to_unsafe_h) ? usage.to_unsafe_h : usage
    row.stringify_keys
  end
  private_class_method :normalize

  def self.ticks_to_usd(ticks)
    ticks.to_i / TICKS_PER_USD
  end
  private_class_method :ticks_to_usd

  def self.rates_for(model, input_tokens)
    table = RATES[RATE_KEYS.find { |key| model.to_s.start_with?(key) }] || RATES["grok-4.3"]
    input_tokens.to_i >= LONG_AT ? table[:long] : table[:short]
  end
  private_class_method :rates_for
end
