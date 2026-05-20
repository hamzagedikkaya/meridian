FactoryBot.define do
  factory :habit_log do
    habit
    date { Date.current }
    completed { true }
    count { 1 }
  end
end
