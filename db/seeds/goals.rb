demo = User.find_by(email: "demo@meridian.local")
return unless demo
return if demo.goals.any?

[
  [ "3 ayda 50K biriktir",  "Birikim hesabında 50K TL hedefi.", "financial", 50_000, "TRY", 3.months.from_now ],
  [ "100 gün kitap oku",    "Her gün en az 30 sayfa.",           "habit",     100,    "gün", 100.days.from_now ],
  [ "10kg kilo ver",         "Sağlıklı şekilde, 6 ay içinde.",   "custom",    10,     "kg",  6.months.from_now ],
  [ "Yeni dil — A2 seviye",  "Almanca A2 sertifikası.",          "custom",    1,      "seviye", 9.months.from_now ]
].each_with_index do |(name, desc, type, target, unit, deadline), i|
  demo.goals.create!(
    name: name, description: desc, target_type: type,
    target_value: target, current_value: 0, unit: unit,
    deadline: deadline, position: i, color: %w[#B8860B #6B8E5A #B85450 #6B8FA0][i % 4]
  )
end

puts "[seed] goals — #{demo.goals.count} goals"
