module Kura
  module_function

  def signup_enabled?
    flag("SIGNUP_ENABLED", default: true)
  end

  def force_ssl?
    flag("FORCE_SSL", default: false)
  end

  def allowed_hosts
    ENV.fetch("KURA_HOST", "").split(/[,\s]+/).map(&:strip).reject(&:blank?)
  end

  def flag(key, default:)
    return default unless ENV.key?(key) && ENV[key].to_s.strip != ""

    !%w[0 false no off].include?(ENV[key].to_s.strip.downcase)
  end
end
