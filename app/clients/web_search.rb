module WebSearch
  class Error < StandardError; end
  class TimeoutError < Error; end

  PROVIDERS = %w[kagi brave].freeze

  def self.provider
    name = ENV.fetch("WEB_SEARCH_PROVIDER", "kagi").to_s.strip.downcase
    PROVIDERS.include?(name) ? name : "kagi"
  end

  def self.client
    case provider
    when "brave" then Brave::Client.new
    else Kagi::Client.new
    end
  end
end
