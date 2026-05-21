demo = User.find_by(email: "demo@meridian.local")
return unless demo
return if demo.events.any?

base = Date.current.beginning_of_month

events = [
  [ "Team standup",        "Daily sync",      "work",     base + 2.days + 9.hours,  30,  "#6B8FA0" ],
  [ "1:1 with manager",    nil,               "work",     base + 5.days + 14.hours, 60,  "#6B8FA0" ],
  [ "Dentist appointment", nil,               "health",   base + 8.days + 11.hours, 45,  "#6B8E5A" ],
  [ "Yoga class",          "Local studio",   "health",   base + 10.days + 18.hours, 60,  "#6B8E5A" ],
  [ "Dinner with friends", "New Italian place", "personal", base + 12.days + 19.hours, 120, "#D4A574" ],
  [ "Annual review",       nil,               "work",     base + 15.days + 10.hours, 90,  "#6B8FA0" ],
  [ "Birthday party",      "Bring gift!",     "personal", base + 22.days + 20.hours, 180, "#D4A574" ],
  [ "Rent due",            "Auto-transfer",  "finance",  base + 28.days + 9.hours,  nil, "#B85450" ]
]

events.each do |title, desc, type, start_at, duration_min, color|
  demo.events.create!(
    title: title, description: desc, event_type: type,
    start_at: start_at, end_at: (duration_min ? start_at + duration_min.minutes : nil),
    color: color
  )
end

puts "[seed] events — #{demo.events.count} events"
