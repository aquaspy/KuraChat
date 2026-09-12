class MarkdownRenderer
  ALLOWED_TAGS = %w[p br strong em a code pre blockquote ul ol li h1 h2 h3 h4 h5 h6 hr
                    table thead tbody tr th td del].freeze
  ALLOWED_ATTR = { "a" => %w[href], "code" => %w[class] }.freeze
  HEADING_SPACE = /^(\#{1,6})([^#\s])/
  HEADING_ANCHOR = %r{<a href="#[^"]*"[^>]*></a>}

  def self.render(markdown)
    text = ChatCompleter::RepetitionGuard.strip_junk(markdown)
    text = text.gsub(HEADING_SPACE, '\1 \2')
    html = Commonmarker.to_html(text, options: {
      extension: { table: true, strikethrough: true, autolink: true, tasklist: false },
      render: { unsafe: false, github_pre_lang: true }
    })
    html = html.gsub(HEADING_ANCHOR, "")
    ActionController::Base.helpers.sanitize(
      html,
      tags: ALLOWED_TAGS,
      attributes: ALLOWED_ATTR
    )
  end
end
