require "test_helper"

class MarkdownRendererTest < ActiveSupport::TestCase
  test "renders markdown and strips scripts" do
    html = MarkdownRenderer.render("**hi** <script>alert(1)</script>")
    assert_includes html, "<strong>hi</strong>"
    assert_not_includes html, "script"
  end

  test "strips grok citation PUA tokens before render" do
    pua = "\uE000"
    junk = "#{pua}markdown:1#{pua}#{pua}l#{pua}https://example.com#{pua}#{pua}r#{pua}Example#{pua}"
    html = MarkdownRenderer.render("Safe answer.\n#{junk}")
    assert_includes html, "Safe answer"
    assert_not_includes html, "markdown:1"
    assert_not_includes html, pua
  end
end
