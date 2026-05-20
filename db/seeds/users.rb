# Seeds two users:
#   admin@meridian.local — your account
#   demo@meridian.local  — pre-populated with fake data in later seed files

User.find_or_create_by!(email: "admin@meridian.local") do |u|
  u.name             = "Admin"
  u.password         = "password123"
  u.timezone         = "Istanbul"
  u.currency         = "TRY"
  u.locale           = "tr"
  u.theme_preference = "dark"
end

User.find_or_create_by!(email: "demo@meridian.local") do |u|
  u.name             = "Demo User"
  u.password         = "demo12345"
  u.timezone         = "Istanbul"
  u.currency         = "TRY"
  u.locale           = "tr"
  u.theme_preference = "dark"
end

puts "[seed] users — #{User.count} total"
