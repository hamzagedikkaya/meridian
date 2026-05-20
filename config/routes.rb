Rails.application.routes.draw do
  devise_for :users

  # Settings
  get  "settings",                to: "settings#show",                as: :settings
  get  "settings/profile",        to: "settings#profile",             as: :profile_settings
  patch "settings/profile",       to: "settings#update_profile"
  get "settings/preferences",    to: "settings#preferences",         as: :preferences_settings
  patch "settings/preferences",   to: "settings#update_preferences"
  get  "settings/data",           to: "settings#data",                as: :data_settings
  get  "settings/notifications",  to: "settings#notifications",       as: :notifications_settings

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Lookbook — ViewComponent preview (dev only)
  if Rails.env.development?
    mount Lookbook::Engine, at: "/lookbook"
  end

  root "pages#home"
end
