# Seeds two users:
#   admin@meridian.local — your account
#   demo@meridian.local  — pre-populated with fake data in later seed files

# Seeding creates accounts whose passwords are, by construction, known. That is
# fine on a laptop and is a full compromise anywhere reachable: Meridian is meant
# to be served on a LAN, so anyone on the Wi-Fi could sign in with them. Refuse to
# run outside development unless the passwords are supplied explicitly.
unless Rails.env.development?
  raise "db/seeds/users.rb creates accounts with known passwords. Set SEED_ADMIN_PASSWORD " \
        "and SEED_DEMO_PASSWORD to run it outside development." if
    ENV["SEED_ADMIN_PASSWORD"].blank? || ENV["SEED_DEMO_PASSWORD"].blank?
end

admin_password = ENV.fetch("SEED_ADMIN_PASSWORD", "password123")
demo_password  = ENV.fetch("SEED_DEMO_PASSWORD",  "demo12345")

User.find_or_create_by!(email: "admin@meridian.local") do |u|
  u.name             = "Admin"
  u.password         = admin_password
  u.timezone         = "Istanbul"
  u.currency         = "TRY"
  u.locale           = "tr"
  u.theme_preference = "dark"
end

User.find_or_create_by!(email: "demo@meridian.local") do |u|
  u.name             = "Demo User"
  u.password         = demo_password
  u.timezone         = "Istanbul"
  u.currency         = "TRY"
  u.locale           = "tr"
  u.theme_preference = "dark"
end

puts "[seed] users — #{User.count} total"
