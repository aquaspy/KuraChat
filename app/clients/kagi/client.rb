require "net/http"
require "json"

module Kagi
  class Error < StandardError; end
  class TimeoutError < Error; end

  class Client
    BASE = URI("https://kagi.com/api/v1")

    def initialize(api_key: ENV["KAGI_API_KEY"])
      @api_key = api_key.to_s
      raise Error, "missing_key" if @api_key.blank?
    end

    def search(query:, recency: nil, limit: 8, extract_count: Integer(ENV.fetch("KAGI_EXTRACT_COUNT", "3")))
      payload = { query: query, workflow: "search", limit: limit }
      if extract_count.positive?
        payload[:extract] = { count: extract_count.clamp(1, 10), timeout: 8 }
      end
      if recency.to_s.in?(%w[day week month])
        payload[:lens] = { time_relative: recency }
      end
      data = post("/search", payload)
      Rails.logger.info("[Kagi] ms=#{data.dig("meta", "ms")} trace=#{data.dig("meta", "trace")}")
      Array(data.dig("data", "search")).take(8).map { |row|
        {
          title: row["title"].to_s,
          url: row["url"].to_s,
          date: row["time"].to_s,
          snippet: row["snippet"].to_s.truncate(2000, omission: "…")
        }
      }
    end

    private
      def post(path, payload)
        req = Net::HTTP::Post.new(URI.join(BASE.to_s + "/", path.delete_prefix("/")))
        req["Authorization"] = "Bearer #{@api_key}"
        req["Content-Type"] = "application/json"
        req["Accept"] = "application/json"
        req.body = JSON.generate(payload)
        http = Net::HTTP.new(BASE.host, BASE.port)
        http.use_ssl = true
        http.open_timeout = 10
        http.read_timeout = 90
        res = http.request(req)
        raise Error, "http_#{res.code}" unless res.is_a?(Net::HTTPSuccess)

        JSON.parse(res.body)
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ETIMEDOUT
        raise TimeoutError, "timeout"
      end
  end
end
