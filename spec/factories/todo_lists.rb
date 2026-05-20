FactoryBot.define do
  factory :todo_list do
    user
    sequence(:name) { |n| "List #{n}" }
    color { "#B8860B" }
  end
end
