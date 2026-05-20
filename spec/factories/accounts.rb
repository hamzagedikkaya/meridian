FactoryBot.define do
  factory :account do
    user
    sequence(:name) { |n| "Account #{n}" }
    account_type { "cash" }
    currency { "TRY" }
    initial_balance_cents { 0 }
    color { "#B8860B" }
  end
end
