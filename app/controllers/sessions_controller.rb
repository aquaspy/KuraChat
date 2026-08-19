class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]
  skip_unlock
  rate_limit to: 20, within: 3.minutes, only: :create,
    with: -> { redirect_to login_path, alert: I18n.t("auth.too_many") }

  def new
    return redirect_to root_path if authenticated? && unlocked?
    redirect_to unlock_path if authenticated?
  end

  def create
    user = User.find_by(email: params[:email].to_s)
    if user&.authenticate(params[:password].to_s)
      login_as user
      redirect_to root_path
    else
      flash.now[:alert] = t("js.invalid_credentials")
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    logout
    redirect_to login_path
  end
end
