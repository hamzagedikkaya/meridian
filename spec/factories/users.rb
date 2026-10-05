FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@meridian.local" }
    name { Faker::Name.name }
    password { "password123" }
    password_confirmation { "password123" }
    # Requests run in the user's zone (UserTimeZoneAndLocale) while specs
    # compute expectations in Time.zone, which is UTC in the test process. A
    # UTC user keeps the two in step at any hour; specs about time zones set
    # one explicitly and pin the clock (spec/requests/api/v1/time_zone_spec.rb).
    timezone { "UTC" }
    currency { "TRY" }
    locale { "en" }
    theme_preference { "dark" }
    weekly_review_day { 0 }
  end
end
