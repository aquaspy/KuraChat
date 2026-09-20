require "application_system_test_case"

class ComposerTest < ApplicationSystemTestCase
  test "attaching and pasting images shows chips and sends them" do
    User.create!(email: "composer@x.com", password: "secret-ok")
    visit login_path
    fill_in "Email", with: "composer@x.com"
    fill_in "Password", with: "secret-ok"
    click_button "Sign in"

    click_button "New chat"
    assert_selector "form.composer"

    attach_file("images[]", Rails.root.join("test/fixtures/files/dot.png"), make_visible: true)
    assert_selector ".composer-chip", count: 1

    page.execute_script(<<~JS)
      const ta = document.querySelector('[data-composer-target="input"]');
      const png = Uint8Array.from(atob("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="), (c) => c.charCodeAt(0));
      const file = new File([png], "paste.png", { type: "image/png" });
      const dt = new DataTransfer();
      dt.items.add(file);
      ta.dispatchEvent(new ClipboardEvent("paste", { clipboardData: dt, bubbles: true, cancelable: true }));
    JS
    assert_selector ".composer-chip", count: 2

    find('[data-composer-target="input"]').set("Look")
    click_button "Send"
    assert_selector ".msg-user:not(.is-echo) .msg-image img", count: 2

    severe = page.driver.browser.logs.get(:browser).select { |log| log.level == "SEVERE" }
    assert_empty severe.select { |log| log.message.include?("composer") }
  end
end
