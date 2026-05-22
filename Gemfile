source "https://rubygems.org"

# --- Core ---
gem "rails", "~> 8.0.2", ">= 8.0.2.1"
gem "propshaft"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"

# --- Frontend / Hotwire ---
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "tailwindcss-rails"

# --- API helpers ---
gem "jbuilder"

# --- Windows tz ---
gem "tzinfo-data", platforms: %i[ windows jruby ]

# --- Solid suite (Rails 8 defaults) ---
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# --- Boot / Deploy ---
gem "bootsnap", require: false
gem "kamal", require: false
gem "thruster", require: false

# --- Auth ---
gem "devise"

# --- UI Components ---
gem "view_component"

# --- Charts & Data ---
gem "chartkick"
gem "groupdate"

# --- Search (Postgres FTS) ---
gem "pg_search"

# --- Ruby 3.4 prep: csv is being removed from stdlib ---
gem "csv"

# --- Money & Recurring ---
gem "money-rails"
gem "ice_cube"

# Pagination handled manually (offset/limit) — keep deps lean.

# --- ActiveStorage variants ---
gem "image_processing", "~> 1.2"

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Security scanner
  gem "brakeman", require: false

  # N+1 static analysis (AST)
  gem "eager_eye", require: false

  # Linting
  gem "rubocop-rails-omakase", require: false
  gem "rubocop-rspec", require: false

  # Testing
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "faker"
  gem "shoulda-matchers"
  gem "simplecov", require: false
end

group :development do
  gem "web-console"
  gem "bullet"          # N+1 detection
  gem "lookbook"        # ViewComponent preview UI
end

group :test do
  gem "capybara"
  gem "selenium-webdriver"
end
