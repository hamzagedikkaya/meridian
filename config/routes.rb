Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # Lookbook — ViewComponent preview (dev only)
  if Rails.env.development?
    mount Lookbook::Engine, at: "/lookbook"
  end

  # Defines the root path route ("/")
  root "pages#home"
end
