FactoryBot.define do
  factory :event do
    user
    sequence(:title) { |n| "Event #{n}" }
    start_at { 1.hour.from_now }
    event_type { "personal" }
    color { "#B8860B" }
  end
end
