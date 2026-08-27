require "net/http"
require "json"
require "cgi"
require "uri"

module Kagi
  class Error < WebSearch::Error; end
  class TimeoutError < WebSearch::TimeoutError; end

  class Client
    BASE = URI("https://kagi.com/api/v1")
    COUNTRY_FOR_LOCALE = { "pt" => "BR", "en" => "US" }.freeze
    SNIPPET_CHARS = 4_000
    DEFAULT_LIMIT = 12
    KEEP = 8
    BUCKETS = %w[
      weather direct_answer infobox news interesting_news search interesting_finds code
    ].freeze

    def initialize(api_key: ENV["KAGI_API_KEY"])
      @api_key = api_key.to_s
      raise Error, "missing_key" if @api_key.blank?
    end

    def search(query:, recency: nil, limit: DEFAULT_LIMIT, extract_count: Integer(ENV.fetch("KAGI_EXTRACT_COUNT", "3")))
      payload = self.class.build_payload(query:, recency:, limit:, extract_count:)
      data = post("/search", payload)
      rows = self.class.normalize(data)
      Rails.logger.info("[Kagi] ms=#{data.dig("meta", "ms")} trace=#{data.dig("meta", "trace")} results=#{rows.size} region=#{payload.dig(:lens, :search_region) || "-"}")
      rows
    end

    def self.build_payload(query:, recency: nil, limit: DEFAULT_LIMIT, extract_count: Integer(ENV.fetch("KAGI_EXTRACT_COUNT", "3")))
      payload = { query: query.to_s, workflow: "search", limit: limit.to_i.clamp(1, 20) }
      if extract_count.to_i.positive?
        payload[:extract] = { count: extract_count.to_i.clamp(1, 10), timeout: 8 }
      end
      lens = {}
      lens[:time_relative] = recency.to_s if recency.to_s.in?(%w[day week month])
      lens[:search_region] = region if region.present?
      payload[:lens] = lens if lens.present?
      payload
    end

    def self.region
      raw = ENV["KAGI_REGION"].to_s.strip.upcase
      raw = COUNTRY_FOR_LOCALE.fetch(I18n.locale.to_s[0, 2], nil) if raw.blank?
      return nil if raw.blank? || raw == "ALL"

      raw
    end

    def self.normalize(payload)
      root = payload["data"].is_a?(Hash) ? payload["data"] : payload
      seen = {}
      BUCKETS.flat_map { |name| Array(root[name]) }.filter_map { |row|
        next unless row.is_a?(Hash)

        url = row["url"].to_s
        next if url.blank? || url.start_with?("/")

        snippet = usable_snippet(row)
        next if snippet.blank?

        site = host_for(row, url)
        next if site.present? && seen[site]

        seen[site] = true if site.present?
        {
          title: CGI.unescapeHTML(row["title"].to_s),
          url: url,
          site: site,
          date: date_for(row),
          snippet: snippet.truncate(SNIPPET_CHARS, omission: "…")
        }
      }.first(KEEP)
    end

    def self.host_for(row, url)
      props = row["props"].is_a?(Hash) ? row["props"] : {}
      host = props["group_id"].to_s
      host = "" if host.blank? || host.start_with?("/") || !host.include?(".")
      host.presence || URI.parse(url).host.to_s.sub(/\Awww\./, "")
    rescue URI::InvalidURIError
      ""
    end

    def self.date_for(row)
      props = row["props"].is_a?(Hash) ? row["props"] : {}
      row["time"].presence ||
        props["published"].presence ||
        props["date"].presence ||
        props["published_date"].presence ||
        ""
    end

    def self.usable_snippet(row)
      cleaned = clean_text(row["snippet"].to_s)
      return "" if cleaned.blank? || chrome?(cleaned)

      cleaned
    end

    def self.clean_text(value)
      text = CGI.unescapeHTML(value.to_s.gsub(/<\/?[^>]+>/, ""))
      lines = text.split(/\n+/).map { |line| line.gsub(/[ \t]+/, " ").strip }.reject(&:blank?)
      lines.reject! { |line| share_line?(line) || chrome_line?(line) }
      lines.shift while lines.first && chrome_line?(lines.first)
      lines.join("\n").strip
    end

    def self.share_line?(line)
      line.match?(%r{facebook\.com/sharer|twitter\.com/intent|x\.com/intent}i) ||
        line.match?(/\A(X\s*)?\[\s*\]\s*\(/) ||
        line.match?(/\A!\[[^\]]*\]\(https?:\/\//)
    end

    def self.chrome_line?(line)
      l = line.to_s.downcase
      return true if share_line?(line)
      return true if l.length < 80 && l.match?(/\Ax\b|\+ mais not[ií]cias|compartilhar|share this/)
      return true if l.length < 280 && l.match?(/cookies?|pol[ií]tica de privacidade|privacy policy|ao continuar navegando|aceitar todos/)

      false
    end

    def self.chrome?(text)
      t = text.to_s.strip.downcase
      return true if t.length < 80 && t.match?(/\Ax\b|mais not[ií]cias|compartilhar|share this/)

      t.match?(/\A(usamos cookies|we use cookies|ao continuar navegando|this site uses cookies)/)
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
