Rails.application.routes.draw do
  devise_for :users, skip: [ :registrations ], controllers: { sessions: "users/sessions" }

  # ActiveStorage's direct-upload endpoint requires no authentication and this
  # app never uses it — every upload is an ordinary multipart form post. Left
  # open it lets an unauthenticated caller on the LAN mint upload tokens and
  # PUT blobs until the disk fills. Application routes are matched before the
  # ActiveStorage routes, so this wins.
  match "/rails/active_storage/direct_uploads", to: proc { [ 404, { "Content-Type" => "text/plain" }, [ "Not Found" ] ] }, via: :all

  # Settings
  get  "settings",                to: "settings#show",                as: :settings
  get  "settings/profile",        to: "settings#profile",             as: :profile_settings
  patch "settings/profile",       to: "settings#update_profile"
  get "settings/preferences",    to: "settings#preferences",         as: :preferences_settings
  patch "settings/preferences",   to: "settings#update_preferences"
  get "settings/data",           to: "settings#data",                as: :data_settings

  # Mobile JSON API (bearer-token auth; consumed by the Flutter app)
  namespace :api do
    namespace :v1 do
      get   "health", to: "health#show"
      post  "session", to: "sessions#create"
      delete "session", to: "sessions#destroy"
      get   "me", to: "me#show"
      patch "me", to: "me#update"
      get   "me/options", to: "me#options"
      patch "me/password", to: "me#update_password"
      get   "home", to: "home#show"
      get   "search", to: "search#index"
      namespace :finance do
        get "dashboard", to: "dashboard#show"
      end
      resources :accounts, only: [ :index, :show, :create, :update, :destroy ] do
        member do
          patch :archive
          patch :unarchive
        end
      end
      resources :transactions, only: [ :index, :show, :create, :update, :destroy ]
      resources :finance_categories, only: [ :index, :show, :create, :update, :destroy ]
      resources :budgets, only: [ :index, :create, :update, :destroy ]
      resources :subscriptions, only: [ :index, :show, :create, :update, :destroy ] do
        member do
          post :charge
        end
      end
      get "currencies", to: "currencies#index"
      resources :habits, only: [ :index, :show, :create, :update, :destroy ] do
        member do
          patch :toggle_today
          patch :archive
          patch :unarchive
          # Any segment reaches the action, so "04.10.2026" gets a JSON
          # invalid_date instead of being split off as a format.
          put "logs/:date", action: :update_log, as: :log, constraints: { date: %r{[^/]+} }, format: false
        end
      end
      resources :goals, only: [ :index, :show, :create, :update, :destroy ] do
        member do
          patch :update_progress
          patch :recalculate
        end
      end
      resources :journal_entries, only: [ :index, :show, :create, :update, :destroy ]
      resources :todo_lists, only: [ :index, :show, :create, :update, :destroy ]
      resources :todos, only: [ :index, :show, :create, :update, :destroy ] do
        member do
          patch :toggle
        end
      end
      resources :events, only: [ :index, :show, :create, :update, :destroy ]
      resources :quick_captures, only: [ :create ]

      # Last: any other /api/v1 path is the API's JSON 404, not Rails' page,
      # the bare /api/v1 (and /api/v1/) included, which "*path" misses.
      match "/", to: "not_found#show", via: :all, format: false, as: nil
      match "*path", to: "not_found#show", via: :all, format: false
    end
  end

  # Finance module
  namespace :finance do
    root "dashboard#index"
    get "category_pie", to: "dashboard#category_pie", as: :category_pie
    resources :transactions
    resources :accounts
    resources :categories
    resources :budgets
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
