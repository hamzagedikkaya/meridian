FactoryBot.define do
  factory :habit do
    user
    sequence(:name) { |n| "Habit #{n}" }
    frequency { "daily" }
    target_count { 1 }
    color { "#B8860B" }
  end
end
