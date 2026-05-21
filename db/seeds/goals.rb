demo = User.find_by(email: "demo@meridian.local")
return unless demo
return if demo.goals.any?

# Link each goal to a real source where possible so progress is computed live.
savings_account = demo.accounts.find_by(name: "Savings")
read_habit      = demo.habits.find_by(name: "Read 30 pages")

specs = [
  { name: "Save 50K in 3 months",  description: "Reach 50K in the savings account.",     target_type: "financial", target_value: 50_000, unit: "TRY",   deadline: 3.months.from_now,  related: savings_account, color: "#B8860B" },
  { name: "Read for 100 days",     description: "At least 30 pages every day.",          target_type: "habit",     target_value: 100,    unit: "days",  deadline: 100.days.from_now,  related: read_habit, color: "#6B8E5A" },
  { name: "Lose 10 kg",            description: "Healthy pace over six months.",         target_type: "custom",    target_value: 10,     unit: "kg",    deadline: 6.months.from_now,  related: nil, color: "#B85450" },
  { name: "Learn German — A2",     description: "Pass the A2 certificate exam.",         target_type: "custom",    target_value: 1,      unit: "level", deadline: 9.months.from_now,  related: nil, color: "#6B8FA0" }
]

specs.each_with_index do |attrs, i|
  demo.goals.create!(attrs.merge(current_value: 0, position: i))
end

# Trigger initial progress calculation so the linked goals show real progress.
demo.goals.active.each(&:recalculate_progress!)

puts "[seed] goals — #{demo.goals.count} goals (linked: financial→#{savings_account&.name || '—'}, habit→#{read_habit&.name || '—'})"
