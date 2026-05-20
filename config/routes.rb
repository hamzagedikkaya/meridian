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

  # Finance module
  namespace :finance do
    root "dashboard#index"
    resources :transactions
    resources :accounts
    resources :categories
    resources :subscriptions
    resource  :transfer, only: [ :new, :create ]
    get "reports", to: "reports#index", as: :reports
    get "export.csv", to: "transactions#export", as: :transactions_export
  end

  # Todos
  resources :todo_lists, except: [ :show ]
  resources :todos do
    member do
      patch :toggle
      patch :reorder
    end
  end

  # Goals
  resources :goals do
    member { patch :recalculate }
  end

  # Backups
  resources :backups, only: [ :index, :show, :create, :destroy ] do
    member { get :download }
    collection { post :restore }
  end

  # Journal
  resources :journal_entries, path: "journal"

  # Habits
  resources :habits do
    member do
      patch :toggle_today
    end
    resources :habit_logs, only: [ :create, :update ], shallow: true
  end

  # Calendar
  get  "calendar",                  to: "calendar#index", as: :calendar
  get  "calendar/:year/:month",     to: "calendar#index", as: :calendar_month, constraints: { year: /\d{4}/, month: /\d{1,2}/ }
  get  "calendar/feed",             to: "calendar#feed",  as: :calendar_feed
  resources :events

  # Search
  get "search", to: "search#index", defaults: { format: :json }, as: :search

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Lookbook — ViewComponent preview (dev only)
  if Rails.env.development?
    mount Lookbook::Engine, at: "/lookbook"
  end

  root "pages#home"
end
