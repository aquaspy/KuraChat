class ApplicationController < ActionController::Base
  include Authentication
  include Locale
  include Locking

  allow_browser versions: :modern unless Rails.env.test?
  stale_when_importmap_changes
end
