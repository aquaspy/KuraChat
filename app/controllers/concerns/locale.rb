module Locale
  extend ActiveSupport::Concern

  included do
    before_action :set_locale
    helper_method :html_lang
  end

  private
    def set_locale
      I18n.locale = locale_from_header
    end

    def locale_from_header
      header = request.headers["Accept-Language"].to_s
      header.split(",").each do |part|
        tag = part.split(";").first.to_s.strip.downcase
        return :pt if tag.start_with?("pt")
        return :en if tag.start_with?("en")
      end
      I18n.default_locale
    end

    def html_lang
      I18n.locale == :pt ? "pt-BR" : "en"
    end
end
