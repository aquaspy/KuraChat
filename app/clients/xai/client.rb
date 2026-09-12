require "net/http"
require "json"
require "openssl"

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

    def stream_response(input:, tools: nil, max_output_tokens: nil,
                        reasoning_effort: ENV.fetch("XAI_REASONING_EFFORT", "low"),
                        prompt_cache_key: nil, &block)
      post_sse(
        "/responses",
        response_body(input:, tools:, max_output_tokens:, reasoning_effort:, stream: true, prompt_cache_key:),
        prompt_cache_key:,
        &block
      )
    end

    def complete(input:, max_output_tokens: nil, reasoning_effort: "none")
      post_json("/responses", response_body(input:, max_output_tokens:, reasoning_effort:, stream: false))
    end

    def self.output_text(response)
      Array(response.is_a?(Hash) ? response["output"] : nil).flat_map { |item|
        next [] unless item.is_a?(Hash)

        Array(item["content"]).filter_map { |part|
          part["text"] if part.is_a?(Hash) && part["text"].present?
        }
      }.join
    end

    private
      def response_body(input:, tools: nil, max_output_tokens: nil, reasoning_effort:, stream:, prompt_cache_key: nil)
        body = {
          model: @model,
          input: input,
          stream: stream,
          store: false,
          reasoning_effort: reasoning_effort
        }
        body[:tools] = tools if tools.present?
        body[:max_output_tokens] = max_output_tokens if max_output_tokens
        body[:prompt_cache_key] = prompt_cache_key if prompt_cache_key.present?
        if stream
          body[:include] = [ "no_inline_citations", "reasoning.encrypted_content" ]
        end
        body
      end

      def http
        Net::HTTP.new(BASE.host, BASE.port).tap do |h|
          h.use_ssl = true
          h.open_timeout = 10
          h.read_timeout = 3600
        end
      end

      def headers(prompt_cache_key: nil)
        h = {
          "Authorization" => "Bearer #{@api_key}",
          "Content-Type" => "application/json",
          "Accept" => "application/json"
        }
        h["x-grok-conv-id"] = prompt_cache_key if prompt_cache_key.present?
        h
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

      def post_sse(path, body, prompt_cache_key: nil)
        conn = nil
        conn = http
        conn.start
        req = Net::HTTP::Post.new(URI.join(BASE.to_s + "/", path.delete_prefix("/")))
        headers(prompt_cache_key:).each { |k, v| req[k] = v }
        req.body = JSON.generate(body)
        conn.request(req) do |res|
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
      ensure
        drop_connection(conn)
      end

      # Close the TCP/TLS socket immediately so the provider can stop generating
      # (and billing output tokens) instead of draining the rest of the SSE.
      def drop_connection(conn)
        return unless conn

        sock = conn.instance_variable_get(:@socket)
        io = sock.respond_to?(:io) ? sock.io : sock
        io.close if io && !io.closed?
        conn.finish if conn.started?
      rescue IOError, OpenSSL::SSL::SSLError
        nil
      end
  end
end
