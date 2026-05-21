demo = User.find_by(email: "demo@meridian.local")
return unless demo
return if demo.journal_entries.any?

moods = JournalEntry::MOODS
samples = [
  [ "Great start to the day",  "good",    "Started with morning yoga, energy stayed up all day." ],
  [ "Heavy meeting day",       "neutral", "Three back-to-back meetings. Felt drained by evening." ],
  [ "Weekend reset",           "great",   "Brunch with friends, movie in the evening. Full reset." ],
  [ "Low energy",              "bad",     "Trouble sleeping, tired the whole day." ],
  [ "New book on the go",      "good",    "First three chapters of The Pragmatic Engineer — really good." ],
  [ "Rainy Sunday",            "neutral", "Stayed home, did some reading. Calm day." ]
]

samples.each_with_index do |(title, mood, text), i|
  entry = demo.journal_entries.create!(
    date: (i * 4).days.ago.to_date,
    title: title,
    mood: mood,
    energy_level: rand(2..5),
    gratitude: "1. Good health\n2. Family support\n3. Work I enjoy",
    tags: [ "reflection", "personal" ].sample(2).join(", ")
  )
  entry.body = "<p>#{text}</p>"
  entry.save!
end

puts "[seed] journal — #{demo.journal_entries.count} entries"
