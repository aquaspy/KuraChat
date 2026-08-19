module Locking
  extend ActiveSupport::Concern

  IDLE_AFTER = 15.minutes

  included do
    before_action :require_unlock
    helper_method :unlocked?
  end

  class_methods do
    def skip_unlock(**options)
      skip_before_action :require_unlock, **options
    end
  end

  private
    def unlocked?
      session[:unlocked_at].present? && session[:unlocked_at] > IDLE_AFTER.ago
    end

    def require_unlock
      return unless authenticated?
      return if unlocked?
      redirect_to unlock_path
    end

    def unlock_session
      session[:unlocked_at] = Time.current
    end

    def lock_session
      session.delete(:unlocked_at)
    end
end
