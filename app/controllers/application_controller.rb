class ApplicationController < ActionController::Base
  include UserTimeZoneAndLocale

  allow_browser versions: :modern

  before_action :authenticate_user!
  before_action :configure_permitted_parameters, if: :devise_controller?
  # Declared after authentication so current_user is known; the API base
  # controller does the same, so the web and the phone agree on "today".
  around_action :switch_time_zone_and_locale

  layout :resolve_layout

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [ :name ])
    devise_parameter_sanitizer.permit(:account_update, keys: [ :name ])
  end

  def switch_time_zone_and_locale(&action)
    with_user_time_zone_and_locale(current_user, &action)
  end

  def resolve_layout
    devise_controller? ? "auth" : "application"
  end
end
