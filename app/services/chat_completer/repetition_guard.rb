class ChatCompleter
  # Detects Grok degeneration: citation PUA tokens, URL floods, or
  # short closing mantras ("Fim." / "Resumo") repeating in the tail.
  class RepetitionGuard
    PUA = "\uE000"
    CITATION_START = "#{PUA}markdown:".freeze
    MARKDOWN_MARKER = /markdown:\d+/
    URL = %r{https?://[^\s#{PUA}\]"'<>]+}
    SHORT_LINE = 48
    MAX_MARKERS = 8
    MAX_URL_HITS = 4
    MAX_LINE_HITS = 4
    TAIL_CHARS = 1_200

    def self.check(text)
      return :citation_token if text.include?(CITATION_START)
      return :citation_flood if text.scan(MARKDOWN_MARKER).size > MAX_MARKERS

      urls = text.scan(URL)
      return :url_repeat if urls.tally.any? { |_, n| n >= MAX_URL_HITS }

      return :closing_loop if closing_loop?(text)

      nil
    end

    def self.truncate(text, reason)
      case reason
      when :citation_token, :citation_flood, :url_repeat
        cut_at_citation(text) || cut_at_url_flood(text) || text
      when :closing_loop
        strip_trailing_repeated_lines(text)
      else
        text
      end
    end

    def self.strip_junk(text)
      safe, stash = protect_code(text.to_s)
      # markdown:Nlurlrtitle  (and partial forms)
      cleaned = safe.gsub(/#{PUA}markdown:\d+#{PUA}(?:#{PUA}l#{PUA}[^#{PUA}]*#{PUA}#{PUA}r#{PUA}[^#{PUA}]*#{PUA})?/, " ")
      cleaned = cleaned.gsub(/#{PUA}+/, " ")
      # [[n]] or [[n]](url) — xAI sometimes omits the URL, or strips the cite
      # with no_inline_citations and leaves the two sides glued. The URL may
      # itself contain parens (e.g. wiki links), so match one nesting level.
      cleaned = cleaned.gsub(/\[\[[0-9]+\]\](?:\((?:[^()]|\([^()]*\))*\))?/, " ")
      cleaned = cleaned.gsub(/(\*\*[^*]+\*\*)([\p{L}\d])/, '\1 \2')
      # Unstick glued sentences, but a period only splits before a capital —
      # bare domains, filenames and abbreviations (example.com, file.txt,
      # e.g.) stay intact. ! and ? rarely sit inside words.
      cleaned = cleaned.gsub(/(\.)(\p{Lu})/, '\1 \2')
      cleaned = cleaned.gsub(/([!?])(\p{L})/, '\1 \2')
      cleaned = cleaned.gsub(/(\p{Ll})(\p{Lu})/, '\1 \2')
      # Split letter+digit glue (de15), but leave ALLCAPS terms (GPT4, H2O);
      # also catch digit-first glue (15anos) while keeping counts (2M).
      cleaned = cleaned.gsub(/(\p{Ll})(\d)/, '\1 \2')
      cleaned = cleaned.gsub(/(\d)(\p{Ll})/, '\1 \2')
      cleaned = collapse_spaces(cleaned)
      # A cite (or a leftover space) sitting just inside **…** becomes
      # `** Limitless**`, which CommonMark leaves as literal asterisks.
      cleaned = cleaned.gsub(/\*\*([^*]+)\*\*/) { "**#{$1.strip}**" }
      restore_code(cleaned.strip, stash)
    end

    # Stashes fenced code blocks and inline code spans behind inert
    # placeholders so cleanup phases never rewrite code. Returns
    # [safe_text, stash]; restore with restore_code.
    def self.protect_code(text)
      sentinel = [ "\uE001", "\uE002", "\uE003" ].find { |s| !text.include?(s) } || "\uE001"
      blocks = []
      stash = ->(code) do
        blocks << code
        "#{sentinel}#{blocks.size - 1}#{sentinel}"
      end

      lines = text.lines
      out = +""
      i = 0
      while i < lines.size
        open = lines[i].match(/\A {0,3}(`{3,}|~{3,})/)
        if open
          char = open[1][0]
          len = open[1].length
          close = /\A {0,3}#{char}{#{len},}[ \t]*(?:\n|\z)/
          j = i + 1
          j += 1 while j < lines.size && !close.match?(lines[j])
          j += 1 if j < lines.size
          out << stash.call(lines[i...j].join)
          i = j
        else
          out << lines[i]
          i += 1
        end
      end

      safe = out.gsub(/``[^`\n]+``|`[^`\n]+`/) { |span| stash.call(span) }
      [ safe, [ sentinel, blocks ] ]
    end

    def self.restore_code(safe, stash)
      sentinel, blocks = stash
      safe.gsub(/#{Regexp.escape(sentinel)}(\d+)#{Regexp.escape(sentinel)}/) { blocks[Regexp.last_match(1).to_i] }
    end

    # Collapse mid-line space runs, but keep leading indentation so
    # nested lists and indented code blocks still parse.
    def self.collapse_spaces(text)
      text.lines.map do |line|
        indent = line[/\A[ \t]*/]
        indent + line[indent.length..].gsub(/[ \t]{2,}/, " ")
      end.join
    end
    private_class_method :collapse_spaces

    def self.closing_loop?(text)
      tail = text.length > TAIL_CHARS ? text[-TAIL_CHARS..] : text
      lines = tail.lines.map { |line| line.strip }.reject(&:empty?)
      return false if lines.size < 6

      lines.last(40).tally.any? { |line, n| line.length <= SHORT_LINE && n >= MAX_LINE_HITS }
    end
    private_class_method :closing_loop?

    def self.cut_at_citation(text)
      idx = text.index(CITATION_START)
      return nil unless idx

      text[0...idx].rstrip
    end
    private_class_method :cut_at_citation

    def self.cut_at_url_flood(text)
      urls = text.scan(URL)
      offender, = urls.tally.max_by { |_, n| n }
      return nil unless offender && urls.count(offender) >= MAX_URL_HITS

      hits = 0
      pos = 0
      while (found = text.index(offender, pos))
        hits += 1
        return text[0...found].rstrip if hits >= MAX_URL_HITS

        pos = found + offender.length
      end
      nil
    end
    private_class_method :cut_at_url_flood

    def self.strip_trailing_repeated_lines(text)
      lines = text.lines
      while lines.size >= 2 && (closing_loop?(lines.join) || mantra_line?(lines.last))
        lines.pop
      end
      lines.join.rstrip
    end
    private_class_method :strip_trailing_repeated_lines

    def self.mantra_line?(line)
      s = line.to_s.strip
      return false if s.empty? || s.length > SHORT_LINE

      s.match?(/\A(?:fim\.?|resposta\.?|\*{0,2}resumo\*{0,2}:?\.?|obrigado\.?|pronto\.?)\z/i)
    end
    private_class_method :mantra_line?
  end
end
