require "net/http"
require "json"

module Brave
  class Error < WebSearch::Error; end
  class TimeoutError < WebSearch::TimeoutError; end

  class Client
    BASE = URI("https://api.search.brave.com/res/v1/web/search")
    FRESHNESS = { "day" => "pd", "week" => "pw", "month" => "pm" }.freeze

    def initialize(api_key: ENV["BRAVE_API_KEY"])
      @api_key = api_key.to_s
      raise Error, "missing_key" if @api_key.blank?
    end

    def search(query:, recency: nil, limit: 8)
      params = {
        q: query.to_s.truncate(400),
        count: limit.to_i.clamp(1, 20),
        extra_snippets: true,
        text_decorations: false,
        result_filter: "web",
        spellcheck: true
      }
      params[:freshness] = FRESHNESS[recency.to_s] if FRESHNESS.key?(recency.to_s)
      params[:search_lang] = I18n.locale.to_s if I18n.locale.present?

      data = get(params)
      rows = self.class.normalize(data)
      Rails.logger.info("[Brave] results=#{rows.size}")
      rows
    end

    def self.normalize(data)
      Array(data.dig("web", "results")).take(8).map { |row|
        extra = Array(row["extra_snippets"]).join("\n")
        snippet = [ row["description"], extra ].compact_blank.join("\n")
        {
          title: row["title"].to_s,
          url: row["url"].to_s,
          date: (row["age"] || row["page_age"]).to_s,
          snippet: snippet.truncate(2000, omission: "…")
        }
      }
    end

    private
      def get(params)
        uri = BASE.dup
        uri.query = URI.encode_www_form(params)
        req = Net::HTTP::Get.new(uri)
        req["Accept"] = "application/json"
        req["X-Subscription-Token"] = @api_key
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 10
        http.read_timeout = 30
        res = http.request(req)
        raise Error, "http_#{res.code}" unless res.is_a?(Net::HTTPSuccess)

        JSON.parse(res.body)
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ETIMEDOUT
        raise TimeoutError, "timeout"
      end
  end
end
