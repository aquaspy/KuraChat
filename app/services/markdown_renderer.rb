class MarkdownRenderer
  ALLOWED_TAGS = %w[p br strong em a code pre blockquote ul ol li h1 h2 h3 h4 hr
                    table thead tbody tr th td del].freeze
  ALLOWED_ATTR = { "a" => %w[href], "code" => %w[class] }.freeze

  def self.render(markdown)
    html = Commonmarker.to_html(markdown.to_s, options: {
      extension: { table: true, strikethrough: true, autolink: true, tasklist: false },
      render: { unsafe: false, github_pre_lang: true }
    })
    ActionController::Base.helpers.sanitize(
      html,
      tags: ALLOWED_TAGS,
      attributes: ALLOWED_ATTR
    )
  end
end
