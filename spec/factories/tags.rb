FactoryBot.define do
  factory :tag do
    user
    sequence(:name) { |n| "tag-#{n}" }
  end
end
