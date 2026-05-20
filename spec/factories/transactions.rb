FactoryBot.define do
  factory :transaction do
    user
    account { association :account, user: user }
    finance_category { association :finance_category, user: user, kind: kind == "transfer" ? "expense" : kind }
    amount_cents { 100_00 }
    kind { "expense" }
    description { "Test transaction" }
    date { Date.current }

    trait :income do
      kind { "income" }
      finance_category { association :finance_category, user: user, kind: "income" }
    end

    trait :transfer do
      kind { "transfer" }
      finance_category { nil }
      related_account { association :account, user: user }
    end
  end
end
