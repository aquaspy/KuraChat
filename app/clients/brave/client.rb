require "net/http"
require "json"

module Brave
  class Error < WebSearch::Error; end
  class TimeoutError < WebSearch::TimeoutError; end

  class Client
    BASE = URI("https://api.search.brave.com/res/v1")
    FRESHNESS = { "day" => "pd", "week" => "pw", "month" => "pm" }.freeze
    SNIPPET_CHARS = 4_000

    def initialize(api_key: ENV["BRAVE_API_KEY"])
      @api_key = api_key.to_s
      raise Error, "missing_key" if @api_key.blank?
    end

    def search(query:, recency: nil, limit: 8, context_tokens: Integer(ENV.fetch("BRAVE_CONTEXT_TOKENS", "4096")))
      urls = limit.to_i.clamp(1, 20)
      tokens = context_tokens.clamp(1_024, 32_768)
      payload = {
        q: query.to_s.truncate(400),
        count: urls,
        maximum_number_of_urls: urls,
        maximum_number_of_tokens: tokens,
        maximum_number_of_tokens_per_url: [ tokens, 2_048 ].min.clamp(512, 8_192),
        context_threshold_mode: "balanced",
        enable_source_metadata: true
      }
      payload[:freshness] = FRESHNESS[recency.to_s] if FRESHNESS.key?(recency.to_s)
      lang = I18n.locale.to_s[0, 2]
      payload[:search_lang] = lang if lang.present?

      data = post("/llm/context", payload)
      rows = self.class.normalize(data)
      Rails.logger.info("[Brave] results=#{rows.size}")
      rows
    end

    def self.normalize(data)
      sources = data["sources"].is_a?(Hash) ? data["sources"] : {}
      rows = Array(data.dig("grounding", "generic"))
      poi = data.dig("grounding", "poi")
      rows += [ poi ] if poi.is_a?(Hash)
      rows += Array(data.dig("grounding", "map"))

      rows.first(8).filter_map { |row|
        next unless row.is_a?(Hash)

        url = row["url"].to_s
        next if url.blank?

        meta = sources[url].is_a?(Hash) ? sources[url] : {}
        age = Array(meta["age"])
        date = age[3].presence || age[1].presence || age[0].to_s
        snippet = Array(row["snippets"]).filter_map { |chunk|
          case chunk
          when String then chunk.presence
          when Hash, Array then JSON.generate(chunk)
          else chunk.to_s.presence
          end
        }.join("\n")
        snippet = meta["description"].to_s if snippet.blank?
        {
          title: (row["title"].presence || meta["title"]).to_s,
          url: url,
          date: date.to_s,
          snippet: snippet.truncate(SNIPPET_CHARS, omission: "…")
        }
      }
    end

    private
      def post(path, payload)
        req = Net::HTTP::Post.new(URI.join(BASE.to_s + "/", path.delete_prefix("/")))
        req["X-Subscription-Token"] = @api_key
        req["Content-Type"] = "application/json"
        req["Accept"] = "application/json"
        req.body = JSON.generate(payload)
        http = Net::HTTP.new(BASE.host, BASE.port)
        http.use_ssl = true
        http.open_timeout = 10
        http.read_timeout = 60
        res = http.request(req)
        raise Error, "http_#{res.code}" unless res.is_a?(Net::HTTPSuccess)

        JSON.parse(res.body)
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ETIMEDOUT
        raise TimeoutError, "timeout"
      end
  end
end
