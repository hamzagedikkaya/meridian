FactoryBot.define do
  factory :todo do
    user
    sequence(:title) { |n| "Task #{n}" }
    priority { "medium" }
    status { "pending" }
  end
end
