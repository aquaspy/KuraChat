require "test_helper"

class MarkdownRendererTest < ActiveSupport::TestCase
  test "renders markdown and strips scripts" do
    html = MarkdownRenderer.render("**hi** <script>alert(1)</script>")
    assert_includes html, "<strong>hi</strong>"
    assert_not_includes html, "script"
  end

  test "strips xAI inline [[n]] citations before render" do
    html = MarkdownRenderer.render("Clever é da Billa.[[1]](https://www.billa.cz/znacky)A Billa vende a linha.")
    assert_includes html, "Clever é da Billa."
    assert_includes html, "A Billa vende a linha."
    assert_not_includes html, "[[1]]"
    assert_not_includes html, "billa.cz"
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
