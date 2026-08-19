require "test_helper"

class MarkdownRendererTest < ActiveSupport::TestCase
  test "renders markdown and strips scripts" do
    html = MarkdownRenderer.render("**hi** <script>alert(1)</script>")
    assert_includes html, "<strong>hi</strong>"
    assert_not_includes html, "script"
  end
end
