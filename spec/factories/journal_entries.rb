FactoryBot.define do
  factory :journal_entry do
    user
    date { Date.current }
    title { "A day" }
    mood { "good" }
  end
end
