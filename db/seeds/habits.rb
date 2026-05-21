demo = User.find_by(email: "demo@meridian.local")
return unless demo
return if demo.habits.any?

habits_data = [
  [ "Morning workout",   "10-minute stretch + yoga.",       "daily",  "#D4A574", 0.85 ],
  [ "Read 30 pages",     "Fiction or non-fiction.",         "daily",  "#6B8FA0", 0.70 ],
  [ "Drink 2L water",    nil,                                "daily",  "#6B8E5A", 0.90 ],
  [ "Write in journal",  "A few lines before bed.",         "daily",  "#B8860B", 0.55 ],
  [ "Meditate 10 min",   "Headspace or just breath work.",  "daily",  "#8B5A00", 0.65 ],
  [ "Gym session",       "Three times per week.",           "weekly", "#B85450", 0.40 ]
]

habits_data.each do |name, desc, freq, color, completion_rate|
  habit = demo.habits.create!(name: name, description: desc, frequency: freq, target_count: 1, color: color)

  # 60 days of logs with realistic completion
  60.times do |i|
    date = (i.days.ago).to_date
    completed = rand < completion_rate
    habit.habit_logs.create!(date: date, completed: completed, count: completed ? 1 : 0)
  end
end

puts "[seed] habits — #{demo.habits.count} habits with #{demo.habit_logs.count} logs"
