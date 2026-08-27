module WebSearch
  class Error < StandardError; end
  class TimeoutError < Error; end

  PROVIDERS = %w[kagi brave].freeze
  LANGUAGE_REGION = { "pt" => "BR" }.freeze

  def self.provider
    name = ENV.fetch("WEB_SEARCH_PROVIDER", "kagi").to_s.strip.downcase
    PROVIDERS.include?(name) ? name : "kagi"
  end

  def self.client
    case provider
    when "brave" then Brave::Client.new
    else Kagi::Client.new
    end
  end

  def self.normalize_region(value)
    raw = value.to_s.strip.upcase
    return nil if raw.blank? || raw == "ALL"
    return raw if raw.match?(/\A[A-Z]{2}\z/)

    nil
  end

  def self.region_from_header(header)
    header.to_s.split(",").each do |part|
      tag = part.split(";").first.to_s.strip
      next if tag.blank?

      parts = tag.split(/[-_]/)
      parts[1..].each do |piece|
        return piece.upcase if piece.match?(/\A[A-Za-z]{2}\z/)
      end
      lang = parts.first.to_s.downcase
      return LANGUAGE_REGION[lang] if LANGUAGE_REGION[lang]
    end
    nil
  end

  def self.region_from_locale(locale)
    LANGUAGE_REGION[locale.to_s[0, 2].downcase]
  end

  def self.region(explicit: nil, locale: I18n.locale, env_key: nil)
    [ ENV[env_key.to_s], ENV["SEARCH_REGION"], explicit ].each do |value|
      next if value.nil?

      raw = value.to_s.strip
      next if raw.empty?
      return nil if raw.upcase == "ALL"
      return raw.upcase if raw.match?(/\A[A-Za-z]{2}\z/)
    end
    region_from_locale(locale)
  end
end
