FactoryBot.define do
  factory :finance_category do
    user
    sequence(:name) { |n| "Category #{n}" }
    kind { "expense" }
    color { "#A09B8E" }
  end
end
