module Locking
  extend ActiveSupport::Concern

  IDLE_AFTER = 15.minutes
  COOKIE_NAME = "kura_auto_lock"

  def self.auto_lock_enabled?(cookies)
    cookies[COOKIE_NAME] == "1"
  end

  def self.session_open?(session, cookies)
    raw = session[:unlocked_at]
    return false if raw.blank?
    return true unless auto_lock_enabled?(cookies)

    at = raw.is_a?(String) ? Time.zone.parse(raw) : raw
    at > IDLE_AFTER.ago
  end

  included do
    before_action :require_unlock
    helper_method :unlocked?, :auto_lock_enabled?
  end

  class_methods do
    def skip_unlock(**options)
      skip_before_action :require_unlock, **options
    end
  end

  private
    def auto_lock_enabled?
      Locking.auto_lock_enabled?(cookies)
    end

    def unlocked?
      Locking.session_open?(session, cookies)
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
