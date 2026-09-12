require "uri"

class ChatCompleter
  class Gone < StandardError; end
  class RepetitionAbort < StandardError
    attr_reader :reason

    def initialize(reason)
      @reason = reason
      super(reason.to_s)
    end
  end

  HEARTBEAT_EVERY = 60
  FLUSH_EVERY = 0.25
  FLUSH_CHARS = 80
  WINDOW_MESSAGES = Integer(ENV.fetch("CHAT_WINDOW_MESSAGES", "40"))
  WINDOW_TOKENS   = Integer(ENV.fetch("CHAT_WINDOW_TOKENS", "32000"))
  KEEP_RECENT     = Integer(ENV.fetch("CHAT_KEEP_RECENT", "16"))
  WEB_SEARCH_TOOL = { type: "web_search" }.freeze

  def self.broadcast_failed(message)
    new(message, locale: I18n.locale).broadcast_failed
  end

  def initialize(assistant_message, locale: I18n.default_locale, xai: nil)
    @assistant = assistant_message
    @conversation = assistant_message.conversation
    @locale = locale
    @user_message = @conversation.messages.where(role: "user").where("id < ?", @assistant.id).last
    @xai = xai
  end

  def run
    return if gone?

    @assistant.update!(status: "streaming")
    broadcast_status(web? ? I18n.t("chat.searching") : I18n.t("chat.thinking"))

    acc = Accumulator.new
    citations = []
    truncated = false
    begin
      stream_released { |event|
        apply_response_event!(event, acc, citations)
        checkout { flush!(acc) } if acc.flush_due?
      }
    rescue RepetitionAbort => e
      Rails.logger.info("[ChatCompleter] repetition_abort message_id=#{@assistant.id} reason=#{e.reason}")
      truncated = true
    end
    checkout { flush!(acc) }
    Rails.logger.info("[ChatCompleter] message_id=#{@assistant.id} chars=#{acc.text.length} web=#{web?}")
    checkout { html_complete!(citations, truncated: truncated || acc.aborted?); auto_title!; maybe_compact! }
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
    picked = []
    prompt = assembled_system_prompt
    est = token_estimate(prompt)
    rows.reverse_each do |message|
      payload = message.as_input
      next unless payload

      cost = token_estimate(payload.to_json)
      break if picked.size + 1 > WINDOW_MESSAGES || est + cost > WINDOW_TOKENS

      picked.unshift(payload)
      est += cost
    end
    [ { role: "system", content: prompt }, *picked ]
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
      prompt = I18n.t("chat.system_prompt", locale: @locale)
      key = web? ? "chat.system_web" : "chat.system_no_web"
      prompt += "\n#{I18n.t(key, locale: @locale)}"
      prompt
    end

    def assembled_system_prompt
      now = Time.zone.now
      prompt = "#{system_prompt}\nCurrent date: #{now.strftime("%Y-%m-%d %A")} (#{Time.zone.tzinfo.identifier})."
      if @conversation.summary.present?
        prompt = "#{prompt}\n\nEarlier conversation summary:\n#{@conversation.summary}"
      end
      prompt
    end

    def reasoning_effort
      if web?
        ENV.fetch("XAI_WEB_REASONING_EFFORT", "medium")
      else
        ENV.fetch("XAI_REASONING_EFFORT", "low")
      end
    end

    def reply_max_tokens
      raw = ENV["CHAT_REPLY_MAX_TOKENS"].to_s.strip
      return nil if raw.empty?

      Integer(raw)
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

      response = xai.complete(
        input: [
          { role: "system", content: "Summarize this conversation excerpt in at most 120 words. Keep facts, names, decisions, and open questions. Same language as the messages. No preamble." },
          { role: "user", content: body.truncate(12_000) }
        ],
        max_output_tokens: 180,
        reasoning_effort: "none"
      )
      text = Xai::Client.output_text(response).strip
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

    def gone?
      !Message.exists?(@assistant.id)
    end

    def checkout(&block)
      raise Gone if gone?

      ActiveRecord::Base.connection_pool.with_connection(&block)
    end

    def stream_released(&block)
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
      xai.stream_response(
        input: windowed_messages,
        tools: (web? ? [ WEB_SEARCH_TOOL ] : nil),
        max_output_tokens: reply_max_tokens,
        reasoning_effort: reasoning_effort,
        &block
      )
    ensure
      stop = true
    end

    def apply_response_event!(event, acc, citations)
      type = event["type"].to_s
      if type == "response.failed" || event["error"].present? && type.end_with?("failed")
        raise Xai::Error, event.dig("response", "error", "message") || event.dig("error", "message") || "generation_failed"
      end

      if type.include?("web_search")
        checkout { broadcast_status(I18n.t("chat.searching")) }
      end

      delta = response_text_delta(event)
      if delta.present?
        acc.add_text(delta)
        if (reason = RepetitionGuard.check(acc.text))
          acc.abort!(reason)
          raise RepetitionAbort, reason
        end
      end

      return unless type == "response.completed" || event["response"].is_a?(Hash) && type.end_with?("completed")

      citations.replace(self.class.citations_from(event["response"] || event))
    end

    def response_text_delta(event)
      return event["delta"] if event["type"].to_s.end_with?("output_text.delta") && event["delta"].is_a?(String)

      delta = event["delta"]
      return delta["text"] if delta.is_a?(Hash) && delta["text"].present?

      nil
    end

    def self.citations_from(response)
      return [] unless response.is_a?(Hash)

      seen = {}
      rows = []
      Array(response["citations"]).each { |item| push_citation!(rows, seen, item) }
      Array(response["output"]).each do |item|
        Array(item.is_a?(Hash) ? item["content"] : nil).each do |part|
          next unless part.is_a?(Hash)

          Array(part["annotations"]).each { |ann| push_citation!(rows, seen, ann) }
        end
      end
      rows
    end

    def self.push_citation!(rows, seen, item)
      url = nil
      title = nil
      case item
      when String
        url = item
      when Hash
        url = item["url"] || item[:url]
        title = item["title"] || item[:title]
      end
      url = url.to_s.strip
      return if url.blank?

      label = citation_title(url, title)
      if seen[url]
        row = rows.find { |r| r["url"] == url }
        if row && label.present? && (row["title"].blank? || row["title"] == url)
          row["title"] = label
        end
        return
      end

      seen[url] = true
      rows << { "title" => label, "url" => url }
    end

    def self.citation_title(url, title)
      raw = title.to_s.strip
      return raw unless raw.blank? || raw.match?(/\A\d+\z/)

      URI.parse(url).host.presence || url
    rescue URI::InvalidURIError
      url
    end

    def flush!(acc)
      return unless acc.text_changed?

      @assistant.update_columns(content: acc.text, updated_at: Time.current)
      acc.mark_flushed!
      broadcast_body
    end

    def html_complete!(citations, truncated: false)
      body = RepetitionGuard.strip_junk(@assistant.content.to_s)
      attrs = {
        status: "complete",
        content: body,
        citations: citations.uniq { |c| c["url"] || c[:url] }
      }
      attrs[:error] = "truncated_repetition" if truncated
      @assistant.update!(attrs)
      broadcast_body
      broadcast_message
    end

    def auto_title!
      first = nil
      return if @conversation.title.present?

      first = @conversation.messages.where(role: "user").chronological.first
      return unless first

      title = request_title(first.content)
      title = title.presence || fallback_title(first.content)
      return if title.blank?

      @conversation.update!(title: title)
      broadcast_title
    rescue StandardError
      @conversation.update!(title: fallback_title(first&.content)) if @conversation.title.blank?
    end

    def broadcast_title
      stream = [ @conversation.user, @conversation ]
      Turbo::StreamsChannel.broadcast_replace_to(
        stream,
        target: ActionView::RecordIdentifier.dom_id(@conversation, :title),
        partial: "conversations/title",
        locals: { conversation: @conversation }
      )
      Turbo::StreamsChannel.broadcast_replace_to(
        stream,
        target: ActionView::RecordIdentifier.dom_id(@conversation, :title_field),
        partial: "conversations/title_field",
        locals: { conversation: @conversation }
      )
    end

    def request_title(text)
      response = xai.complete(
        input: [
          { role: "system", content: "Reply with a conversation title only. Max 8 words, no quotes." },
          { role: "user", content: text.to_s.truncate(400) }
        ],
        max_output_tokens: 24,
        reasoning_effort: "none"
      )
      fallback_title(Xai::Client.output_text(response))
    end

    def fallback_title(text)
      text.to_s.strip.split(/\s+/).first(8).join(" ").truncate(60, omission: "")
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

    def broadcast_body
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
      attr_reader :text, :abort_reason

      def initialize
        @text = +""
        @last_flush = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @flushed_len = 0
        @aborted = false
        @abort_reason = nil
      end

      def aborted?
        @aborted
      end

      def add_text(chunk)
        return if @aborted

        @text << chunk.to_s
      end

      def abort!(reason)
        @aborted = true
        @abort_reason = reason
        @text = RepetitionGuard.truncate(@text, reason)
        @text = RepetitionGuard.strip_junk(@text)
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
