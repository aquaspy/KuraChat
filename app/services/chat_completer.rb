class ChatCompleter
  class Gone < StandardError; end

  MAX_TOOL_ROUNDS = 4
  MAX_SEARCHES = 2
  HEARTBEAT_EVERY = 60
  FLUSH_EVERY = 0.25
  FLUSH_CHARS = 80
  WINDOW_MESSAGES = Integer(ENV.fetch("CHAT_WINDOW_MESSAGES", "40"))
  WINDOW_TOKENS   = Integer(ENV.fetch("CHAT_WINDOW_TOKENS", "12000"))
  KEEP_RECENT     = Integer(ENV.fetch("CHAT_KEEP_RECENT", "16"))

  WEB_SEARCH_TOOL = {
    type: "function",
    function: {
      name: "web_search",
      description: "Search the live web with Kagi. Use for current events, prices, news, or facts that may have changed. Prefer one precise query. Do not search for general knowledge you already know.",
      parameters: {
        type: "object",
        properties: {
          query: { type: "string", description: "Search query" },
          recency: {
            type: "string",
            enum: %w[day week month any],
            description: "Optional recency. Omit or any for no time filter."
          }
        },
        required: [ "query" ]
      }
    }
  }.freeze

  def self.broadcast_failed(message)
    new(message, locale: I18n.locale).broadcast_failed
  end

  def initialize(assistant_message, locale: I18n.default_locale, xai: nil, kagi: nil)
    @assistant = assistant_message
    @conversation = assistant_message.conversation
    @locale = locale
    @user_message = @conversation.messages.where(role: "user").where("id < ?", @assistant.id).last
    @searches = 0
    @xai = xai
    @kagi = kagi
  end

  def run
    return if gone?

    @assistant.update!(status: "streaming")
    broadcast_status(web? ? I18n.t("chat.searching") : I18n.t("chat.thinking"))

    @tools = web? ? [ WEB_SEARCH_TOOL ] : nil
    citations = []
    rounds = 0

    loop do
      rounds += 1
      raise "tool loop overflow" if rounds > MAX_TOOL_ROUNDS

      acc = Accumulator.new
      finish = nil
      payload = windowed_messages
      stream_released(payload) { |chunk|
        delta = chunk.dig("choices", 0, "delta") || {}
        finish = chunk.dig("choices", 0, "finish_reason") || finish
        acc.add_text(delta["content"]) if delta["content"]
        acc.add_tool_calls(delta["tool_calls"]) if delta["tool_calls"]
        checkout { flush!(acc) } if acc.flush_due?
      }
      checkout { flush!(acc) }

      if acc.tool_calls.empty? || finish == "stop"
        checkout { html_complete!(citations); auto_title!; maybe_compact! }
        break
      end

      checkout do
        persist_hidden_tool_calls(acc.tool_calls)
        acc.tool_calls.each do |tc|
          result, cites = execute_tool(tc)
          citations.concat(cites)
          persist_tool_result(tc, result)
        end
        broadcast_status(I18n.t("chat.searching"))
      end
    end
  rescue ChatCompleter::Gone
    nil
  rescue => e
    fail!(e)
  ensure
    if @assistant && Message.exists?(@assistant.id) && @assistant.reload.status == "streaming"
      fail!(RuntimeError.new("incomplete_stream"))
    end
  end

  def windowed_messages
    through = @conversation.summarized_through_id
    rows = @conversation.messages.chronological.where.not(id: @assistant.id)
    rows = rows.where("id > ?", through) if through.present?
    rows = rows.to_a
    compact_before = @user_message&.id
    picked = []
    prompt = assembled_system_prompt
    est = token_estimate(prompt)
    group_history(rows).reverse_each do |group|
      payloads = group.filter_map { |message| message.as_openai(compact_tools_before: compact_before) }
      next if payloads.empty?
      next unless legal_tool_group?(group, payloads)

      cost = token_estimate(payloads.to_json)
      break if picked.size + payloads.size > WINDOW_MESSAGES || est + cost > WINDOW_TOKENS

      picked.unshift(*payloads)
      est += cost
    end
    [ { role: "system", content: prompt }, *picked ]
  end

  def group_history(rows)
    groups = []
    i = 0
    while i < rows.size
      m = rows[i]
      if m.tool_calls?
        group = [ m ]
        i += 1
        while i < rows.size && rows[i].role == "tool"
          group << rows[i]
          i += 1
        end
        groups << group
      else
        groups << [ m ]
        i += 1
      end
    end
    groups
  end

  def legal_tool_group?(group, payloads)
    head = group.first
    return true unless head.tool_calls?

    parent = payloads.find { |p| p[:tool_calls].present? }
    return false unless parent

    ids = parent[:tool_calls].map { |tc| tc["id"] || tc[:id] }.compact.sort
    got = payloads.select { |p| p[:role] == "tool" }.map { |p| p[:tool_call_id] }.compact.sort
    ids.present? && ids == got
  end

  def broadcast_failed
    return if gone?

    Turbo::StreamsChannel.broadcast_replace_to(
      [ @conversation.user, @conversation ],
      target: ActionView::RecordIdentifier.dom_id(@assistant),
      partial: "messages/message",
      locals: { message: @assistant, conversation: @conversation }
    )
  end

  private
    def web?
      @user_message&.web?
    end

    def system_prompt
      prompt = I18n.t("chat.system_prompt", locale: @locale, ui_locale: @locale)
      prompt += "\n#{I18n.t("chat.system_no_web", locale: @locale)}" unless web?
      prompt
    end

    def assembled_system_prompt
      prompt = system_prompt
      if @conversation.summary.present?
        prompt = "#{prompt}\n\nEarlier conversation summary:\n#{@conversation.summary}"
      end
      prompt
    end

    def maybe_compact!
      visible = @conversation.messages.transcript.chronological.where("id < ?", @assistant.id).to_a
      return if visible.size <= KEEP_RECENT

      cutoff = visible.last(KEEP_RECENT).first.id
      older = visible.select { |message| message.id < cutoff }
      through = @conversation.summarized_through_id
      older = older.select { |message| through.nil? || message.id > through }
      excerpt = older.filter_map { |message|
        next if message.content.blank?

        "#{message.role}: #{message.content.to_s.truncate(500)}"
      }.join("\n")
      return if excerpt.blank?

      prior = @conversation.summary.to_s.strip
      body = +""
      body << "Previous summary:\n#{prior}\n\n" if prior.present?
      body << "New messages:\n#{excerpt}"

      response = xai.chat(
        messages: [
          { role: "system", content: "Summarize this conversation excerpt in at most 120 words. Keep facts, names, decisions, and open questions. Same language as the messages. No preamble." },
          { role: "user", content: body.truncate(12_000) }
        ],
        max_tokens: 180,
        reasoning_effort: "none"
      )
      text = response.dig("choices", 0, "message", "content").to_s.strip
      return if text.blank?

      @conversation.update!(summary: text, summarized_through_id: older.last.id)
    rescue Xai::Error, Xai::TimeoutError
      nil
    end

    def token_estimate(str)
      (str.to_s.bytesize / 4.0).ceil
    end

    def xai
      @xai ||= Xai::Client.new
    end

    def kagi
      @kagi ||= Kagi::Client.new
    end

    def gone?
      !Message.exists?(@assistant.id)
    end

    def checkout(&block)
      raise Gone if gone?

      ActiveRecord::Base.connection_pool.with_connection(&block)
    end

    def stream_released(payload, &block)
      stop = false
      Thread.new do
        loop do
          sleep HEARTBEAT_EVERY
          break if stop
          checkout { @assistant.update_columns(updated_at: Time.current) }
        rescue ChatCompleter::Gone
          break
        end
      end
      ActiveRecord::Base.connection_pool.release_connection
      xai.stream_chat(messages: payload, tools: @tools, &block)
    ensure
      stop = true
    end

    def flush!(acc)
      return unless acc.text_changed?

      @assistant.update_columns(content: acc.text, updated_at: Time.current)
      acc.mark_flushed!
      broadcast_body_plain
    end

    def html_complete!(citations)
      @assistant.update!(
        status: "complete",
        content: @assistant.content.to_s,
        citations: citations.uniq { |c| c["url"] || c[:url] }
      )
      broadcast_message
    end

    def auto_title!
      return if @conversation.title.present?

      first = @conversation.messages.where(role: "user").chronological.first
      return unless first

      title = request_title(first.content) || fallback_title(first.content)
      return if title.blank?

      @conversation.update!(title: title)
      Turbo::StreamsChannel.broadcast_replace_to(
        [ @conversation.user, @conversation ],
        target: ActionView::RecordIdentifier.dom_id(@conversation, :title),
        partial: "conversations/title",
        locals: { conversation: @conversation }
      )
    rescue Xai::Error, Xai::TimeoutError
      @conversation.update!(title: fallback_title(first&.content)) if @conversation.title.blank?
    end

    def request_title(text)
      response = xai.chat(
        messages: [
          { role: "system", content: "Reply with a conversation title only. Max 8 words, no quotes." },
          { role: "user", content: text.to_s.truncate(400) }
        ],
        max_tokens: 24,
        reasoning_effort: "none"
      )
      fallback_title(response.dig("choices", 0, "message", "content"))
    end

    def fallback_title(text)
      text.to_s.strip.split(/\s+/).first(8).join(" ").truncate(60, omission: "")
    end

    def persist_hidden_tool_calls(tool_calls)
      @conversation.messages.create!(
        role: "assistant",
        status: "complete",
        content: nil,
        raw: { "tool_calls" => tool_calls }
      )
    end

    def persist_tool_result(tool_call, result)
      id = tool_call["id"] or raise ArgumentError, "missing tool_call id"
      @conversation.messages.create!(
        role: "tool",
        content: result.is_a?(String) ? result : JSON.generate(result),
        raw: { "tool_call_id" => id, "name" => tool_call.dig("function", "name") }
      )
    end

    def execute_tool(tc)
      name = tc.dig("function", "name")
      args = JSON.parse(tc.dig("function", "arguments").presence || "{}")
      return [ { "error" => "unknown_tool" }, [] ] unless name == "web_search"
      return [ { "error" => "search_budget_exhausted" }, [] ] if @searches >= MAX_SEARCHES

      @searches += 1
      query = args["query"].to_s
      recency = args["recency"]
      results = with_heartbeat { kagi.search(query: query, recency: recency) }
      cites = results.map { |r| { "title" => r[:title], "url" => r[:url] } }
      [ { "query" => query, "results" => results }, cites ]
    rescue Kagi::Error, JSON::ParserError
      [ { "error" => "search_failed" }, [] ]
    end

    def with_heartbeat
      stop = false
      Thread.new do
        loop do
          sleep HEARTBEAT_EVERY
          break if stop
          checkout { @assistant.update_columns(updated_at: Time.current) }
        rescue ChatCompleter::Gone
          break
        end
      end
      ActiveRecord::Base.connection_pool.release_connection
      yield
    ensure
      stop = true
    end

    def fail!(error)
      return if gone?

      Rails.logger.error("[ChatCompleter] #{error.class}: #{error.message}")
      code = error.message.to_s == "missing_key" ? "missing_key" : "generation_failed"
      @assistant.update!(status: "failed", error: code)
      broadcast_failed
    rescue ActiveRecord::RecordNotFound
      nil
    end

    def broadcast_status(text)
      Turbo::StreamsChannel.broadcast_replace_to(
        [ @conversation.user, @conversation ],
        target: ActionView::RecordIdentifier.dom_id(@assistant, :status),
        html: %(<p class="msg-status" id="#{ActionView::RecordIdentifier.dom_id(@assistant, :status)}">#{ERB::Util.h(text)}</p>)
      )
    end

    def broadcast_body_plain
      Turbo::StreamsChannel.broadcast_replace_to(
        [ @conversation.user, @conversation ],
        target: ActionView::RecordIdentifier.dom_id(@assistant, :body),
        partial: "messages/body",
        locals: { message: @assistant }
      )
    end

    def broadcast_message
      Turbo::StreamsChannel.broadcast_replace_to(
        [ @conversation.user, @conversation ],
        target: ActionView::RecordIdentifier.dom_id(@assistant),
        partial: "messages/message",
        locals: { message: @assistant, conversation: @conversation }
      )
    end

    class Accumulator
      attr_reader :text, :tool_calls

      def initialize
        @text = +""
        @tool_calls = []
        @last_flush = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @flushed_len = 0
      end

      def add_text(chunk)
        @text << chunk.to_s
      end

      def add_tool_calls(deltas)
        Array(deltas).each do |delta|
          i = (delta["index"] || delta[:index] || 0).to_i
          @tool_calls[i] ||= { "id" => nil, "type" => "function", "function" => { "name" => +"", "arguments" => +"" } }
          slot = @tool_calls[i]
          slot["id"] = delta["id"] if delta["id"].present?
          slot["type"] = delta["type"] if delta["type"].present?
          fn = delta["function"] || {}
          slot["function"]["name"] << fn["name"].to_s
          slot["function"]["arguments"] << fn["arguments"].to_s
        end
      end

      def flush_due?
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        grown = @text.length - @flushed_len
        grown >= FLUSH_CHARS || (grown.positive? && (now - @last_flush) >= FLUSH_EVERY)
      end

      def text_changed?
        @text.length != @flushed_len
      end

      def mark_flushed!
        @flushed_len = @text.length
        @last_flush = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
end
