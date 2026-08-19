require "test_helper"

class AuthFlowTest < ActionDispatch::IntegrationTest
  test "signup login lock and logout" do
    get signup_path
    assert_response :success

    post signup_path, params: { email: "you@x.com", password: "secret-ok", password_confirmation: "secret-ok" }
    assert_redirected_to root_path
    follow_redirect!
    assert_response :success

    post lock_path
    assert_redirected_to unlock_path

    post unlock_path, params: { password: "wrong-pass" }
    assert_response :unprocessable_entity

    post unlock_path, params: { password: "secret-ok" }
    assert_redirected_to root_path

    delete logout_path
    assert_redirected_to login_path
  end

  test "signup can be closed" do
    ENV["SIGNUP_ENABLED"] = "false"
    get signup_path
    assert_redirected_to login_path
  ensure
    ENV.delete("SIGNUP_ENABLED")
  end

  test "pt from accept language" do
    get login_path, headers: { "Accept-Language" => "pt-BR,pt;q=0.9" }
    assert_includes @response.body, "Entrar"
  end
end
