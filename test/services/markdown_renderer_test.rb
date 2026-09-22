require "test_helper"

class MarkdownRendererTest < ActiveSupport::TestCase
  test "renders markdown and strips scripts" do
    html = MarkdownRenderer.render("**hi** <script>alert(1)</script>")
    assert_includes html, "<strong>hi</strong>"
    assert_not_includes html, "script"
  end

  test "atx headings work with and without a space after the hashes" do
    spaced = MarkdownRenderer.render("### 2. Hello")
    tight = MarkdownRenderer.render("###2. Hello")
    assert_includes spaced, "<h3>"
    assert_includes spaced, "2. Hello"
    assert_includes tight, "<h3>"
    assert_includes tight, "2. Hello"
    assert_not_includes tight, "###2"
    assert_not_includes spaced, "<a>"
  end

  test "bold still renders when a space sat inside the markers" do
    html = MarkdownRenderer.render("técnicas ** Limitless** e ** Six Eyes**.")
    assert_includes html, "<strong>Limitless</strong>"
    assert_includes html, "<strong>Six Eyes</strong>"
    assert_not_includes html, "** Limitless"
    assert_not_includes html, "** Six"
  end

  test "a full-sentence bold line becomes strong, not literal asterisks" do
    html = MarkdownRenderer.render("**Sim, dá pra pedir, mas com jeitinho e respeito.**")
    assert_includes html, "<strong>"
    assert_not_includes html, "**Sim"
  end

  test "strips xAI inline [[n]] citations before render" do
    html = MarkdownRenderer.render("Clever é da Billa.[[1]](https://www.billa.cz/znacky)A Billa vende a linha.")
    assert_includes html, "Clever é da Billa."
    assert_includes html, "A Billa vende a linha."
    assert_not_includes html, "[[1]]"
    assert_not_includes html, "billa.cz"
  end

  test "unsticks heading and number glues left after silent cite removal" do
    html = MarkdownRenderer.render("AparênciaJovem de15 anos. PersonalidadeBondoso.")
    assert_includes html, "Aparência Jovem"
    assert_includes html, "de 15 anos"
    assert_includes html, "Personalidade Bondoso"
    assert_not_includes html, "AparênciaJovem"
    assert_not_includes html, "de15"
  end

  test "strips grok citation PUA tokens before render" do
    pua = "\uE000"
    junk = "#{pua}markdown:1#{pua}#{pua}l#{pua}https://example.com#{pua}#{pua}r#{pua}Example#{pua}"
    html = MarkdownRenderer.render("Safe answer.\n#{junk}")
    assert_includes html, "Safe answer"
    assert_not_includes html, "markdown:1"
    assert_not_includes html, pua
  end

  test "links keep their href and open in a new tab" do
    html = MarkdownRenderer.render("[Example](https://example.com/x) and https://example.com/docs plus [m](mailto:a@b.co)")
    assert_includes html, 'href="https://example.com/x"'
    assert_includes html, 'href="https://example.com/docs"'
    assert_includes html, 'href="mailto:a@b.co"'
    assert_includes html, 'target="_blank"'
    assert_includes html, 'rel="noopener noreferrer nofollow"'
  end

  test "unsafe link protocols stay stripped" do
    html = MarkdownRenderer.render("[click](javascript:alert(1)) [d](data:text/html,hi)")
    assert_not_includes html, "javascript"
    assert_not_includes html, "data:text"
    assert_not_includes html, "target="
  end

  test "code language class and table alignment survive sanitize" do
    html = MarkdownRenderer.render("```ruby\nputs 1\n```\n")
    assert_includes html, 'class="language-ruby"'
    aligned = MarkdownRenderer.render("| a |\n|:---:|\n| x |\n")
    assert_includes aligned, 'align="center"'
  end

  test "fenced code blocks pass through untouched" do
    md = "```sh\n#!/bin/bash\nusers.map(&:name)\n#not a heading\n```\nVisit https://example.com/docs now."
    html = MarkdownRenderer.render(md)
    assert_includes html, "#!/bin/bash"
    assert_includes html, "users.map"
    assert_includes html, "#not a heading"
    assert_includes html, 'href="https://example.com/docs"'
  end

  test "inline code spans pass through untouched" do
    html = MarkdownRenderer.render("Use `x = [[1]]` and `myVar` ok.")
    assert_includes html, "<code>x = [[1]]</code>"
    assert_includes html, "<code>myVar</code>"
  end

  test "nested lists stay nested and indented code stays code" do
    html = MarkdownRenderer.render("- a\n  - b\n")
    assert_equal 2, html.scan("<ul>").size
    code = MarkdownRenderer.render("Para:\n\n    code_line(1)\n")
    assert_includes code, "<pre><code>code_line(1)"
  end

  test "prose cleanup leaves urls, abbreviations and model names alone" do
    html = MarkdownRenderer.render("See https://example.com/docs, e.g. file.txt, GPT4 and H2O.")
    assert_includes html, "e.g."
    assert_includes html, "file.txt"
    assert_includes html, "GPT4"
    assert_includes html, "H2O"
    assert_includes html, 'href="https://example.com/docs"'
  end

  test "tight headings are repaired mid-document" do
    html = MarkdownRenderer.render("Intro\n\n###2. Hello\n")
    assert_includes html, "<h3>2. Hello</h3>"
  end

  test "splits a table header glued to a heading" do
    md = "### Principais diferenças| Aspecto | Orca |\n|---|---|\n| x | y |\n"
    html = MarkdownRenderer.render(md)
    assert_includes html, "<h3>Principais diferenças</h3>"
    assert_includes html, "<table>"
    assert_includes html, "<th>Aspecto</th>"
    assert_not_includes html, "diferenças|"
  end

  test "leaves a heading with pipes alone when no table follows" do
    html = MarkdownRenderer.render("### A | B\n\nSome text\n")
    assert_includes html, "<h3>A | B</h3>"
    assert_not_includes html, "<table>"
  end

  test "splits a list item glued to a heading" do
    html = MarkdownRenderer.render("### Resumo- item one\n- item two\n")
    assert_includes html, "<h3>Resumo</h3>"
    assert_includes html, "<ul>"
    assert_includes html, "<li>item one</li>"
    assert_includes html, "<li>item two</li>"
  end

  test "splits an ordered item glued to a heading" do
    html = MarkdownRenderer.render("### Ranking1. Ana\n2. Bia\n")
    assert_includes html, "<h3>Ranking</h3>"
    assert_includes html, "<ol>"
  end

  test "leaves hyphenated headings alone without list context" do
    html = MarkdownRenderer.render("### Pré- processamento\nTexto\n")
    assert_includes html, "<h3>Pré- processamento</h3>"
    assert_not_includes html, "<ul>"
  end

  test "leaves spaced dashes in headings alone even before a list" do
    html = MarkdownRenderer.render("### Prós - contras\n- item\n")
    assert_includes html, "<h3>Prós - contras</h3>"
    assert_includes html, "<li>item</li>"
  end

  test "bold glued to a digit still renders" do
    html = MarkdownRenderer.render("**Quantos lounges principais tem?**4 lounges de embarque:")
    assert_includes html, "<strong>Quantos lounges principais tem?</strong>"
    assert_includes html, "4 lounges"
    assert_not_includes html, "**Quantos"
  end

  test "splits list items glued onto one line" do
    md = "**Quantos lounges principais tem?**4 lounges de embarque:" \
      "- Lounge 1 (Schengen)- Lounge 2 (não-Schengen, perto de D/E)" \
      "- Lounge 3 (não-Schengen, perto de F/G)- Lounge 4O Mc Donald's está no 2 e no 3."
    html = MarkdownRenderer.render(md)
    assert_includes html, "<strong>Quantos lounges principais tem?</strong>"
    assert_includes html, "<ul>"
    assert_includes html, "<li>Lounge 1 (Schengen)</li>"
    assert_includes html, "<li>Lounge 2 (não-Schengen, perto de D/E)</li>"
    assert_includes html, "<li>Lounge 3 (não-Schengen, perto de F/G)</li>"
    assert_equal 4, html.scan("<li>").size
  end

  test "leaves single mid-line dashes and emphasis in prose alone" do
    html = MarkdownRenderer.render("Ele disse- vai embora. Prós - contras ficam. Área *airside* (após) e *x* (y).")
    assert_not_includes html, "<ul>"
    assert_includes html, "<em>airside</em>"
  end

  test "mid-line unglue skips table rows and code" do
    html = MarkdownRenderer.render("| (a)- x | (b)- y |\n|:---|:---|\n| 1 | 2 |\n")
    assert_includes html, "<table>"
    code = MarkdownRenderer.render("```\nx:- a (c)- b\n```\n")
    assert_includes code, "x:- a (c)- b"
  end
end
