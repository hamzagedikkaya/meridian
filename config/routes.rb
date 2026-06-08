Rails.application.routes.draw do
  devise_for :users

  # Settings
  get  "settings",                to: "settings#show",                as: :settings
  get  "settings/profile",        to: "settings#profile",             as: :profile_settings
  patch "settings/profile",       to: "settings#update_profile"
  get "settings/preferences",    to: "settings#preferences",         as: :preferences_settings
  patch "settings/preferences",   to: "settings#update_preferences"
  get "settings/data",           to: "settings#data",                as: :data_settings

  # Finance module
  namespace :finance do
    root "dashboard#index"
    get "category_pie", to: "dashboard#category_pie", as: :category_pie
    resources :transactions
    resources :accounts
    resources :categories
    resources :subscriptions
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
    member do
      patch :recalculate
      patch :update_progress
    end
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
  get  "calendar/week",             to: "calendar#week",  as: :calendar_week
  get  "calendar/week/:date",       to: "calendar#week",  as: :calendar_week_at, constraints: { date: /\d{4}-\d{2}-\d{2}/ }
  get  "calendar/:year/:month",     to: "calendar#index", as: :calendar_month, constraints: { year: /\d{4}/, month: /\d{1,2}/ }
  get  "calendar/feed",             to: "calendar#feed",  as: :calendar_feed
  resources :events do
    member do
      patch :move
      patch :reschedule
    end
  end

  # Quick capture
  resources :quick_captures, only: [ :create ]

  # Weekly reviews
  resources :weekly_reviews, only: [ :index, :new, :create, :show, :edit, :update ]

  # Focus sessions
  resources :focus_sessions, only: [ :create, :update ]

  # Insights
  get "insights", to: "insights#index", as: :insights

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
