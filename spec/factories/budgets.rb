FactoryBot.define do
  factory :budget do
    user
    finance_category { association :finance_category, user: user, kind: "expense" }
    monthly_limit_cents { 500_00 }
  end
end
