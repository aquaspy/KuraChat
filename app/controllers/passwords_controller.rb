class PasswordsController < ApplicationController
  rate_limit to: 10, within: 3.minutes, only: :update,
    by: -> { current_user.id },
    with: -> { redirect_to edit_password_path, alert: I18n.t("auth.too_many") }

  def edit
  end

  def update
    unless current_user.authenticate(params[:current_password].to_s)
      flash.now[:alert] = t("js.wrong_password")
      render :edit, status: :unprocessable_entity
      return
    end

    if current_user.update(password: params[:password].to_s, password_confirmation: params[:password_confirmation].to_s)
      user = current_user
      reset_session
      login_as user
      redirect_to root_path, notice: t("auth.password_changed")
    else
      flash.now[:alert] = current_user.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end
end
