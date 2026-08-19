require "net/http"
require "json"

module Xai
  class Error < StandardError; end
  class TimeoutError < Error; end

  class Client
    BASE = URI("https://api.x.ai/v1")

    def initialize(api_key: ENV["XAI_API_KEY"], model: ENV.fetch("XAI_MODEL", "grok-4.3"))
      @api_key = api_key.to_s
      @model = model
      raise Error, "missing_key" if @api_key.blank?
    end

    def stream_chat(messages:, tools: nil, max_tokens: 8192,
                    reasoning_effort: ENV.fetch("XAI_REASONING_EFFORT", "low"), &block)
      body = { model: @model, messages: messages, stream: true, max_tokens: max_tokens, reasoning_effort: reasoning_effort }
      if tools.present?
        body[:tools] = tools
        body[:parallel_tool_calls] = false
        body[:tool_choice] = "auto"
      end
      post_sse("/chat/completions", body, &block)
    end

    def chat(messages:, max_tokens: 24, reasoning_effort: "none")
      post_json("/chat/completions", {
        model: @model, messages: messages, stream: false, max_tokens: max_tokens, reasoning_effort: reasoning_effort
      })
    end

    private
      def http
        Net::HTTP.new(BASE.host, BASE.port).tap do |h|
          h.use_ssl = true
          h.open_timeout = 10
          h.read_timeout = 3600
        end
      end

      def headers
        {
          "Authorization" => "Bearer #{@api_key}",
          "Content-Type" => "application/json",
          "Accept" => "application/json"
        }
      end

      def post_json(path, body)
        req = Net::HTTP::Post.new(URI.join(BASE.to_s + "/", path.delete_prefix("/")))
        headers.each { |k, v| req[k] = v }
        req.body = JSON.generate(body)
        res = http.request(req)
        raise Error, "http_#{res.code}" unless res.is_a?(Net::HTTPSuccess)

        JSON.parse(res.body)
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ETIMEDOUT
        raise TimeoutError, "timeout"
      end

      def post_sse(path, body)
        req = Net::HTTP::Post.new(URI.join(BASE.to_s + "/", path.delete_prefix("/")))
        headers.each { |k, v| req[k] = v }
        req.body = JSON.generate(body)
        http.request(req) do |res|
          raise Error, "http_#{res.code}" unless res.is_a?(Net::HTTPSuccess)

          buf = +""
          res.read_body do |chunk|
            buf << chunk.to_s.tr("\r", "")
            while (idx = buf.index("\n\n"))
              block = buf.slice!(0, idx + 2)
              data = block.each_line.filter_map { |line|
                line.start_with?("data:") ? line.delete_prefix("data:").strip : nil
              }.join
              next if data.empty? || data == "[DONE]"

              yield JSON.parse(data)
            end
          end
        end
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ETIMEDOUT
        raise TimeoutError, "timeout"
      end
  end
end
