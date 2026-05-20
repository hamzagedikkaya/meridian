demo = User.find_by(email: "demo@meridian.local")
return unless demo
return if demo.journal_entries.any?

moods = JournalEntry::MOODS
samples = [
  [ "Iyi bir başlangıç",     "good",    "Sabah yoga ile başladım, gün boyu enerjim yerindeydi." ],
  [ "Yoğun toplantı günü",   "neutral", "Üç tane back-to-back toplantı. Akşam tükenmiş hissettim." ],
  [ "Hafta sonu kaçamağı",   "great",   "Arkadaşlarla kahvaltı, akşam sinema. Tam bir reset günü." ],
  [ "Düşük enerji",          "bad",     "Uyumakta zorlandım, gün boyu yorgundum." ],
  [ "Yeni kitap başladım",   "good",    "The Pragmatic Engineer'ın ilk üç bölümü çok iyi." ],
  [ "Yağmurlu Pazar",        "neutral", "Evde ders çalıştım, sakin geçti." ]
]

samples.each_with_index do |(title, mood, text), i|
  entry = demo.journal_entries.create!(
    date: (i * 4).days.ago.to_date,
    title: title,
    mood: mood,
    energy_level: rand(2..5),
    gratitude: "1. Sağlığım\n2. Aile desteği\n3. İşim",
    tags: [ "reflection", "personal" ].sample(2).join(", ")
  )
  entry.body = "<p>#{text}</p>"
  entry.save!
end

puts "[seed] journal — #{demo.journal_entries.count} entries"
