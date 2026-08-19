module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :current_user, :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def current_user
      @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
    end

    def authenticated?
      current_user.present?
    end

    def require_authentication
      return if authenticated?
      redirect_to login_path
    end

    def login_as(user)
      reset_session unless current_user&.id == user.id
      session[:user_id] = user.id
      session[:unlocked_at] = Time.current
      @current_user = user
    end

    def logout
      reset_session
      @current_user = nil
    end
end
