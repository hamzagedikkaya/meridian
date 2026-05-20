FactoryBot.define do
  factory :goal do
    user
    sequence(:name) { |n| "Goal #{n}" }
    target_type { "custom" }
    target_value { 100 }
    current_value { 0 }
    unit { "TRY" }
    status { "active" }
  end
end
