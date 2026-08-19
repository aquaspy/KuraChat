class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]
  skip_unlock only: %i[new create]
  before_action :require_signup_enabled
  rate_limit to: 10, within: 3.minutes, only: :create,
    with: -> { redirect_to signup_path, alert: I18n.t("auth.too_many") }

  def new
    redirect_to root_path if authenticated? && unlocked?
  end

  def create
    user = User.new(
      email: params[:email].to_s,
      password: params[:password].to_s,
      password_confirmation: params[:password_confirmation].to_s
    )

    if user.save
      login_as user
      redirect_to root_path
    else
      flash.now[:alert] = user.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
    end
  end

  private
    def require_signup_enabled
      return if Kura.signup_enabled?
      redirect_to login_path, alert: t("auth.signup_closed")
    end
end
