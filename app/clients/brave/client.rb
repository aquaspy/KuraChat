require "net/http"
require "json"
require "cgi"

module Brave
  class Error < WebSearch::Error
    attr_reader :http_status, :code

    def initialize(message, http_status: nil, code: nil)
      super(message)
      @http_status = http_status
      @code = code.to_s.presence
    end

    def option_not_in_plan?
      code == "OPTION_NOT_IN_PLAN"
    end

    def plan_blocked?
      option_not_in_plan? || message.to_s.match?(/not included in the plan/i)
    end
  end
  class TimeoutError < WebSearch::TimeoutError; end

  # Uses whichever Brave Search capability the API key actually has.
  # Search plan → LLM Context (page extracts). Legacy Free and plans
  # without that endpoint → Web Search (titles, snippets, news).
  class Client
    BASE = URI("https://api.search.brave.com/res/v1")
    FRESHNESS = { "day" => "pd", "week" => "pw", "month" => "pm" }.freeze
    SNIPPET_CHARS = 16_000
    DEFAULT_LIMIT = 20
    DEFAULT_TOKENS = 8_192
    ENDPOINTS = %w[auto llm web].freeze

    class << self
      def endpoint
        state[:endpoint]
      end

      def endpoint=(value)
        state[:endpoint] = value
      end

      def lean?
        state[:lean]
      end

      def lean=(value)
        state[:lean] = value
      end

      def reset!
        @state = { endpoint: nil, lean: false }
      end

      def state
        @state ||= { endpoint: nil, lean: false }
      end
    end

    def initialize(api_key: ENV["BRAVE_API_KEY"])
      @api_key = api_key.to_s
      raise Error, "missing_key" if @api_key.blank?
    end

    def search(query:, recency: nil, region: nil, limit: DEFAULT_LIMIT, context_tokens: Integer(ENV.fetch("BRAVE_CONTEXT_TOKENS", DEFAULT_TOKENS.to_s)))
      last_error = nil
      adapters.each do |adapter|
        richness_order.each do |lean|
          begin
            rows = invoke(adapter, query:, recency:, region:, limit:, context_tokens:, lean:)
            Brave::Client.endpoint = adapter
            Brave::Client.lean = lean
            return rows
          rescue Error => e
            last_error = e
            raise unless e.plan_blocked?
          end
        end
      end
      raise last_error if last_error

      []
    end

    def self.build_payload(query:, recency: nil, region: nil, limit: DEFAULT_LIMIT, context_tokens: DEFAULT_TOKENS, lean: false)
      urls = limit.to_i.clamp(1, 50)
      payload = { q: query.to_s.truncate(400), count: urls }
      unless lean
        tokens = context_tokens.to_i.clamp(1_024, 32_768)
        payload[:maximum_number_of_urls] = urls
        payload[:maximum_number_of_tokens] = tokens
        payload[:maximum_number_of_tokens_per_url] = [ tokens, 4_096 ].min.clamp(512, 8_192)
      end
      country = country_for(region:)
      payload[:country] = country if country.present?
      payload[:freshness] = FRESHNESS[recency.to_s] if FRESHNESS.key?(recency.to_s)
      lang = search_lang
      payload[:search_lang] = lang if lang.present?
      payload
    end

    def self.build_web_params(query:, recency: nil, region: nil, limit: DEFAULT_LIMIT, lean: false)
      params = {
        q: query.to_s.truncate(400),
        count: limit.to_i.clamp(1, 20)
      }
      unless lean
        params[:extra_snippets] = true
        params[:text_decorations] = false
      end
      country = country_for(region:)
      params[:country] = country if country.present?
      params[:freshness] = FRESHNESS[recency.to_s] if FRESHNESS.key?(recency.to_s)
      lang = search_lang
      params[:search_lang] = lang if lang.present?
      params
    end

    def self.country_for(region: nil)
      WebSearch.region(explicit: region, env_key: "BRAVE_COUNTRY")
    end

    def self.country
      country_for
    end

    def self.search_lang
      ENV["BRAVE_SEARCH_LANG"].to_s.strip.downcase.presence
    end

    def self.configured_endpoint
      name = ENV.fetch("BRAVE_ENDPOINT", "auto").to_s.strip.downcase
      ENDPOINTS.include?(name) ? name : "auto"
    end

    def self.normalize(data)
      sources = data["sources"].is_a?(Hash) ? data["sources"] : {}
      rows = Array(data.dig("grounding", "generic"))
      poi = data.dig("grounding", "poi")
      rows += [ poi ] if poi.is_a?(Hash)
      rows += Array(data.dig("grounding", "map"))

      rows.filter_map { |row|
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
          site: (meta["hostname"].presence || meta["site_name"]).to_s,
          date: date.to_s,
          snippet: snippet.truncate(SNIPPET_CHARS, omission: "…")
        }
      }
    end

    def self.normalize_web(data)
      news = Array(data.dig("news", "results"))
      web = Array(data.dig("web", "results"))
      (news + web).filter_map { |row|
        next unless row.is_a?(Hash)

        url = row["url"].to_s
        next if url.blank?

        snippets = []
        snippets << clean_text(row["description"]) if row["description"].present?
        Array(row["extra_snippets"]).each { |chunk|
          text = clean_text(chunk)
          snippets << text if text.present?
        }
        {
          title: row["title"].to_s,
          url: url,
          site: (row.dig("meta_url", "hostname").presence || row.dig("profile", "name")).to_s,
          date: (row["page_age"].presence || row["age"]).to_s,
          snippet: snippets.join("\n").truncate(SNIPPET_CHARS, omission: "…")
        }
      }.uniq { |row| row[:url] }
    end

    def self.clean_text(value)
      CGI.unescapeHTML(value.to_s.gsub(/<[^>]+>/, "")).squish
    end

    private
      def adapters
        case self.class.configured_endpoint
        when "web" then %w[web]
        when "llm" then %w[llm]
        else
          case self.class.endpoint
          when "web" then %w[web]
          when "llm" then %w[llm web]
          else %w[llm web]
          end
        end
      end

      def richness_order
        self.class.lean? ? [ true ] : [ false, true ]
      end

      def invoke(adapter, query:, recency:, region:, limit:, context_tokens:, lean:)
        if adapter == "web"
          search_web(query:, recency:, region:, limit:, lean:)
        else
          search_llm(query:, recency:, region:, limit:, context_tokens:, lean:)
        end
      end

      def search_llm(query:, recency:, region:, limit:, context_tokens:, lean:)
        payload = self.class.build_payload(query:, recency:, region:, limit:, context_tokens:, lean:)
        data = post("/llm/context", payload)
        rows = self.class.normalize(data)
        Rails.logger.info("[Brave] llm results=#{rows.size} lean=#{lean} country=#{payload[:country] || "-"}")
        rows
      end

      def search_web(query:, recency:, region:, limit:, lean:)
        params = self.class.build_web_params(query:, recency:, region:, limit:, lean:)
        data = get("/web/search", params)
        rows = self.class.normalize_web(data)
        Rails.logger.info("[Brave] web results=#{rows.size} lean=#{lean} country=#{params[:country] || "-"}")
        rows
      end

      def post(path, payload)
        req = Net::HTTP::Post.new(uri_for(path))
        apply_headers(req)
        req["Content-Type"] = "application/json"
        req.body = JSON.generate(payload)
        perform(req)
      end

      def get(path, params)
        uri = uri_for(path)
        uri.query = URI.encode_www_form(params)
        req = Net::HTTP::Get.new(uri)
        apply_headers(req)
        perform(req)
      end

      def uri_for(path)
        URI.join(BASE.to_s + "/", path.delete_prefix("/"))
      end

      def apply_headers(req)
        req["X-Subscription-Token"] = @api_key
        req["Accept"] = "application/json"
      end

      def perform(req, retried: false)
        http = Net::HTTP.new(BASE.host, BASE.port)
        http.use_ssl = true
        http.open_timeout = 10
        http.read_timeout = 60
        res = http.request(req)
        if res.is_a?(Net::HTTPTooManyRequests) && !retried
          sleep 1.2
          return perform(req, retried: true)
        end
        raise_http!(res) unless res.is_a?(Net::HTTPSuccess)

        JSON.parse(res.body)
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ETIMEDOUT
        raise TimeoutError, "timeout"
      end

      def raise_http!(res)
        code = nil
        detail = nil
        parsed = JSON.parse(res.body.to_s) rescue nil
        if parsed.is_a?(Hash) && parsed["error"].is_a?(Hash)
          code = parsed["error"]["code"].to_s.presence
          detail = parsed["error"]["detail"].to_s.presence
        end
        Rails.logger.warn("[Brave] http_#{res.code} #{code} #{detail}")
        raise Error.new("http_#{res.code}", http_status: res.code.to_i, code: code)
      end
  end
end
