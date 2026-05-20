FactoryBot.define do
  factory :weekly_review do
    user
    week_starting { Date.current.beginning_of_week }
  end
end
