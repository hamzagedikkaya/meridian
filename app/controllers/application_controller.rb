class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  before_action :authenticate_user!
  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :set_locale

  layout :resolve_layout

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [ :name ])
    devise_parameter_sanitizer.permit(:account_update, keys: [ :name ])
  end

  def set_locale
    I18n.locale = current_user&.locale&.to_sym || I18n.default_locale
  end

  def resolve_layout
    devise_controller? ? "auth" : "application"
  end
end
