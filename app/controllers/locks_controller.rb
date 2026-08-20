class LocksController < ApplicationController
  skip_unlock only: %i[show create lock]
  rate_limit to: 20, within: 3.minutes, only: :create,
    with: -> { redirect_to unlock_path, alert: I18n.t("auth.too_many") }

  def show
  end

  def create
    if current_user.authenticate(params[:password].to_s)
      unlock_session
      redirect_to root_path
    else
      flash.now[:alert] = t("js.wrong_password")
      render :show, status: :unprocessable_entity
    end
  end

  def lock
    lock_session
    redirect_to unlock_path
  end

  def toggle_auto_lock
    current_user.update!(auto_lock: !current_user.auto_lock?)
    redirect_back fallback_location: root_path
  end
end
