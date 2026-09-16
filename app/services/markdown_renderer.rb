class MarkdownRenderer
  ALLOWED_TAGS = %w[p br strong em a code pre blockquote ul ol li h1 h2 h3 h4 h5 h6 hr
                    table thead tbody tr th td del].freeze
  # Flat list: sanitize takes an array here. A per-tag hash is silently
  # ignored and would strip every attribute, including all hrefs.
  ALLOWED_ATTRS = %w[href class align lang title].freeze
  HEADING_SPACE = /^(\#{1,6})([^#\s])/
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
    text = ChatCompleter::RepetitionGuard.strip_junk(markdown)
    safe, stash = ChatCompleter::RepetitionGuard.protect_code(text)
    fixed = safe.gsub(HEADING_SPACE, '\1 \2')
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
end
