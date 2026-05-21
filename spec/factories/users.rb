FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@meridian.local" }
    name { Faker::Name.name }
    password { "password123" }
    password_confirmation { "password123" }
    timezone { "Istanbul" }
    currency { "TRY" }
    locale { "en" }
    theme_preference { "dark" }
    weekly_review_day { 0 }
  end
end
