demo = User.find_by(email: "demo@meridian.local")
return unless demo
return if demo.goals.any?

# Link each goal to a real source where possible so progress is computed live.
savings_account = demo.accounts.find_by(name: "Birikim")
read_habit      = demo.habits.find_by(name: "Kitap oku")

specs = [
  { name: "3 ayda 50K biriktir",  description: "Birikim hesabında 50K TL hedefi.",  target_type: "financial", target_value: 50_000, unit: "TRY",   deadline: 3.months.from_now,  related: savings_account, color: "#B8860B" },
  { name: "100 gün kitap oku",    description: "Her gün en az 30 sayfa.",            target_type: "habit",     target_value: 100,    unit: "gün",   deadline: 100.days.from_now,  related: read_habit, color: "#6B8E5A" },
  { name: "10kg kilo ver",        description: "Sağlıklı şekilde, 6 ay içinde.",    target_type: "custom",    target_value: 10,     unit: "kg",    deadline: 6.months.from_now,  related: nil, color: "#B85450" },
  { name: "Yeni dil — A2 seviye", description: "Almanca A2 sertifikası.",            target_type: "custom",    target_value: 1,      unit: "seviye", deadline: 9.months.from_now, related: nil, color: "#6B8FA0" }
]

specs.each_with_index do |attrs, i|
  demo.goals.create!(attrs.merge(current_value: 0, position: i))
end

# Trigger initial progress calculation so the linked goals show real progress.
demo.goals.active.each(&:recalculate_progress!)

puts "[seed] goals — #{demo.goals.count} goals (linked: financial→#{savings_account&.name || '—'}, habit→#{read_habit&.name || '—'})"
