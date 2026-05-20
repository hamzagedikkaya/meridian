FactoryBot.define do
  factory :focus_session do
    user
    started_at { Time.current }
    duration_seconds { 1500 }
    mode { "focus" }
  end
end
