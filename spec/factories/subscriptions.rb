FactoryBot.define do
  factory :subscription do
    user
    account { association :account, user: user }
    sequence(:name) { |n| "Subscription #{n}" }
    amount_cents { 100_00 }
    frequency { "monthly" }
    active { true }
    start_date { Date.current }
    next_charge_on { Date.current + 1.month }
  end
end
