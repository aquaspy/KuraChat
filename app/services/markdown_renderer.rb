class MarkdownRenderer
  ALLOWED_TAGS = %w[p br strong em a code pre blockquote ul ol li h1 h2 h3 h4 h5 h6 hr
                    table thead tbody tr th td del].freeze
  # Flat list: sanitize takes an array here. A per-tag hash is silently
  # ignored and would strip every attribute, including all hrefs.
  ALLOWED_ATTRS = %w[href class align lang title].freeze
  HEADING_SPACE = /^(\#{1,6})([^#\s])/
  # Grok sometimes drops the newline after an ATX heading, gluing the
  # next block to it ("### Title| a |" / "### Resumo- item"). The glued
  # line alone is ambiguous ("### A | B" is a legit heading), so a split
  # only happens when the FOLLOWING line confirms the block: a table
  # delimiter row, or a list item with the same marker flavor.
  GLUED_TABLE = /\A(\#{1,6}\s+\S.*?)(\|.*\|\s*)\z/
  TABLE_DELIMITER = /\A\s*\|[\s:|\-]*-[\s:|\-]*\|?\s*\z/
  GLUED_LIST = /\A(\#{1,6}\s+\S.*?\S)([-*+]\s+\S.*|\d{1,3}\.\s+\S.*)\s*\z/
  UNORDERED_ITEM = /\A\s*[-*+]\s+\S/
  ORDERED_ITEM = /\A\s*\d{1,3}\.\s+\S/
  # Grok sometimes drops the newlines for a whole block, gluing the
  # lead-in and every list item onto one line ("...embarque:- a)- b").
  # One glued marker alone is ambiguous (a sloppy dash), so a split
  # only happens when the SAME line holds 2+ markers glued to boundary
  # punctuation: repetition confirms the collapsed list. Table rows
  # and quotes stay untouched.
  GLUED_MIDLINE_ITEM = /(?<=[:;.)\]!?])([-*+])(?=[ \t]+\S)/
  # Comrak emits an empty anchor inside every heading; drop it so
  # headings carry no dead fragment links.
  HEADING_ANCHOR = %r{<a href="#[^"]*"[^>]*></a>}

  # Keeps the allowlist and opens external links in a new tab,
  # like the Sources list.
  class LinkScrubber < Rails::HTML::PermitScrubber
    def initialize
      super()
      self.tags = MarkdownRenderer::ALLOWED_TAGS
      self.attributes = MarkdownRenderer::ALLOWED_ATTRS
    end

    def scrub(node)
      result = super
      if node.element? && node.name == "a" && node["href"].to_s.match?(%r{\Ahttps?://}i)
        node["target"] = "_blank"
        node["rel"] = "noopener noreferrer nofollow"
      end
      result
    end
  end
  private_constant :LinkScrubber

  def self.render(markdown)
    # Structural repairs run before strip_junk: its space insertions
    # (e.g. "Ranking1" -> "Ranking 1") would erase the glue evidence.
    safe, stash = ChatCompleter::RepetitionGuard.protect_code(markdown.to_s)
    fixed = ChatCompleter::RepetitionGuard.strip_junk(
      unglue_midline_lists(unglue_heading_blocks(safe.gsub(HEADING_SPACE, '\1 \2')))
    )
    html = Commonmarker.to_html(
      ChatCompleter::RepetitionGuard.restore_code(fixed, stash),
      options: {
        extension: { table: true, strikethrough: true, autolink: true, tasklist: false },
        render: { unsafe: false, github_pre_lang: false }
      }
    )
    html = html.gsub(HEADING_ANCHOR, "")
    ActionController::Base.helpers.sanitize(html, scrubber: LinkScrubber.new)
  end

  def self.unglue_heading_blocks(text)
    lines = text.lines
    lines.each_with_index.map do |line, i|
      nxt = lines[i + 1]
      if (m = line.match(GLUED_TABLE)) && nxt&.match?(TABLE_DELIMITER)
        "#{m[1].rstrip}\n#{m[2].strip}\n"
      elsif (m = line.match(GLUED_LIST)) && list_confirmed?(m[2], nxt) && !marker_contaminated?(m[1], m[2])
        "#{m[1].rstrip}\n#{m[2].strip}\n"
      else
        line
      end
    end.join
  end
  private_class_method :unglue_heading_blocks

  def self.unglue_midline_lists(text)
    text.lines.map do |line|
      next line if line.include?("|") || line.match?(/\A\s*>/)

      marker = line.scan(GLUED_MIDLINE_ITEM).flatten.tally.find { |_, n| n >= 2 }&.first
      next line if marker.nil?

      line.gsub(/(?<=[:;.)\]!?])#{Regexp.escape(marker)}(?=[ \t]+\S)/, "\n#{marker}")
    end.join
  end
  private_class_method :unglue_midline_lists

  def self.list_confirmed?(glued, nxt)
    return false if nxt.nil?

    nxt.match?(glued.match?(/\A\d{1,3}\./) ? ORDERED_ITEM : UNORDERED_ITEM)
  end
  private_class_method :list_confirmed?

  # A spaced marker inside either half means the heading itself uses
  # that marker ("### Prós - contras"), so the glue point is not safe.
  def self.marker_contaminated?(head, glued)
    marker = glued[/\A(?:\d{1,3}\.|[-*+])/]
    spaced = marker.match?(/\d/) ? /\d{1,3}\.\s/ : / #{Regexp.escape(marker)} /
    head.match?(spaced) || glued.sub(/\A#{Regexp.escape(marker)}\s+/, "").match?(spaced)
  end
  private_class_method :marker_contaminated?
end
