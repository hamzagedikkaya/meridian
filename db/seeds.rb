# Meridian seed orchestrator.
# Run with: bin/rails db:seed
# Idempotent — safe to run repeatedly.

puts "[seed] Starting Meridian seed…"

[
  "users",
  "finance"
].each do |seed_file|
  path = Rails.root.join("db/seeds/#{seed_file}.rb")
  if path.exist?
    puts "[seed] → #{seed_file}"
    load path
  end
end

puts "[seed] Done."
