module Locking
  extend ActiveSupport::Concern

  IDLE_AFTER = 15.minutes

  def self.session_open?(session, user)
    raw = session[:unlocked_at]
    return false if raw.blank?
    return true unless user&.auto_lock?

    at = raw.is_a?(String) ? Time.zone.parse(raw) : raw
    at > IDLE_AFTER.ago
  end

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
      Locking.session_open?(session, current_user)
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
