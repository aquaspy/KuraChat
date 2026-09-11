require "test_helper"

class RepetitionGuardTest < ActiveSupport::TestCase
  PUA = "\uE000"

  test "detects citation token and truncates before it" do
    prose = "Resposta útil sobre o tema."
    junk = "#{PUA}markdown:1#{PUA}#{PUA}l#{PUA}https://a.example#{PUA}#{PUA}r#{PUA}A#{PUA}"
    text = "#{prose}\n#{junk}"
    assert_equal :citation_token, ChatCompleter::RepetitionGuard.check(text)
    assert_equal prose, ChatCompleter::RepetitionGuard.truncate(text, :citation_token)
  end

  test "detects closing mantra loops" do
    prose = "Aqui está a análise completa do caso.\n\n"
    loop = ([ "Fim." ] * 8 + [ "Resposta." ] * 4).join("\n")
    text = prose + loop
    assert_equal :closing_loop, ChatCompleter::RepetitionGuard.check(text)
    truncated = ChatCompleter::RepetitionGuard.truncate(text, :closing_loop)
    assert_includes truncated, "análise completa"
    assert_operator truncated.length, :<, text.length
    assert_no_match(/Fim\.\nFim\.\nFim\.\nFim/, truncated)
  end

  test "detects repeated URLs" do
    url = "https://news.example/story"
    text = "Intro.\n" + ([ url ] * 5).join("\n")
    assert_equal :url_repeat, ChatCompleter::RepetitionGuard.check(text)
  end

  test "strip_junk removes PUA citation blocks" do
    raw = "Hi #{PUA}markdown:2#{PUA}#{PUA}l#{PUA}https://x.test#{PUA}#{PUA}r#{PUA}X#{PUA} there"
    assert_equal "Hi  there", ChatCompleter::RepetitionGuard.strip_junk(raw)
  end

  test "strip_junk removes inline [[n]](url) cites and unsticks the next sentence" do
    raw = "Sim, a Clever é da Billa.[[1]](https://www.billa.cz/znacky)A Billa vende a linha.[[2]](https://example.com/x)"
    cleaned = ChatCompleter::RepetitionGuard.strip_junk(raw)
    assert_equal "Sim, a Clever é da Billa. A Billa vende a linha.", cleaned
    refute_includes cleaned, "[[1]]"
    refute_includes cleaned, "billa.cz"
  end

  test "clean prose is not flagged" do
    text = "Uma resposta normal com um link [fonte](https://ok.example) e fim."
    assert_nil ChatCompleter::RepetitionGuard.check(text)
  end
end
