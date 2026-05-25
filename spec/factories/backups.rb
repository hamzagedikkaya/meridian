FactoryBot.define do
  factory :backup do
    user
    status { "succeeded" }
    meridian_version { Backup::MERIDIAN_VERSION }
    schema_version { "20251201000000" }
    size_bytes { 1024 }
  end
end
