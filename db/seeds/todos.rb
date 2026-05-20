demo = User.find_by(email: "demo@meridian.local")
return unless demo
return if demo.todos.any?

work = demo.todo_lists.create!(name: "Work", color: "#6B8FA0", position: 0)
home = demo.todo_lists.create!(name: "Home", color: "#6B8E5A", position: 1)
shop = demo.todo_lists.create!(name: "Shopping", color: "#D4A574", position: 2)

[
  [ "Review PR #234",                "Code review for the auth refactor.", work, "high",   "in_progress", 1.day.from_now ],
  [ "Sprint planning notes",         nil,                                   work, "medium", "pending",     2.days.from_now ],
  [ "Renew domain",                  nil,                                   home, "urgent", "pending",     3.hours.from_now ],
  [ "Call electrician",              "About the kitchen socket.",           home, "high",   "pending",     Date.current ],
  [ "Buy milk, bread, eggs",         nil,                                   shop, "low",    "pending",     1.day.from_now ],
  [ "Order birthday gift",           "Mum's birthday next week.",           shop, "medium", "pending",     4.days.from_now ],
  [ "Read 'The Pragmatic Engineer'", "Chapter 4–6.",                         nil,  "low",    "pending",     1.week.from_now ],
  [ "Deploy v1.2",                   nil,                                   work, "urgent", "pending",     2.hours.ago ],
  [ "Fix kitchen faucet",            "Buy the parts first.",                home, "medium", "done",        1.day.ago ],
  [ "Schedule dentist",              nil,                                   home, "low",    "done",        3.days.ago ]
].each_with_index do |(title, body, list, priority, status, due), i|
  demo.todos.create!(
    title: title, body: body, todo_list: list,
    priority: priority, status: status, due_at: due, position: i
  )
end

puts "[seed] todos — #{demo.todos.count} todos in #{demo.todo_lists.count} lists"
