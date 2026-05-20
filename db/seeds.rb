# Meridian seed orchestrator.
# Run with: bin/rails db:seed
# Idempotent — safe to run repeatedly.

puts "[seed] Starting Meridian seed…"

[
  "users"
  # "finance",    # Aşama 2'de eklenecek
  # "todos",      # Aşama 3
  # "habits",     # Aşama 4
  # "events",     # Aşama 5
  # "journal",    # Aşama 6
  # "goals"       # Aşama 6.5
].each do |seed_file|
  path = Rails.root.join("db/seeds/#{seed_file}.rb")
  if path.exist?
    puts "[seed] → #{seed_file}"
    load path
  end
end

puts "[seed] Done."
