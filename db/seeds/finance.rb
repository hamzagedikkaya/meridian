# Finance seed — runs against the demo user.
# Creates accounts, categories, ~3 months of transactions, 5 subscriptions.

demo = User.find_by(email: "demo@meridian.local")
unless demo
  puts "[seed] finance — demo user missing, skipping"
  return
end

if demo.transactions.any?
  puts "[seed] finance — demo user already has #{demo.transactions.count} transactions, skipping"
  return
end

# Accounts
cash = demo.accounts.create!(name: "Wallet",      account_type: "cash",        currency: "TRY", initial_balance_cents: 50_00,    color: "#D4A574")
bank = demo.accounts.create!(name: "Main bank",   account_type: "bank",        currency: "TRY", initial_balance_cents: 1_500_00, color: "#6B8FA0")
card = demo.accounts.create!(name: "Credit card", account_type: "credit_card", currency: "TRY", initial_balance_cents: 0,        color: "#B85450")
save = demo.accounts.create!(name: "Savings",     account_type: "savings",     currency: "TRY", initial_balance_cents: 10_000_00, color: "#6B8E5A")

# Income categories
salary  = demo.finance_categories.create!(name: "Salary",    kind: "income", color: "#6B8E5A")
freelance = demo.finance_categories.create!(name: "Freelance", kind: "income", color: "#D4A574")

# Expense categories
groceries   = demo.finance_categories.create!(name: "Groceries",     kind: "expense", color: "#D4915A")
restaurants = demo.finance_categories.create!(name: "Restaurants",   kind: "expense", color: "#B85450")
transport   = demo.finance_categories.create!(name: "Transport",     kind: "expense", color: "#6B8FA0")
bills       = demo.finance_categories.create!(name: "Bills",         kind: "expense", color: "#A09B8E")
subscriptions_cat = demo.finance_categories.create!(name: "Subscriptions", kind: "expense", color: "#B8860B")
entertainment = demo.finance_categories.create!(name: "Entertainment", kind: "expense", color: "#8B5A00")

vendors = [ "Whole Foods", "Trader Joe's", "Uber", "Verizon", "Starbucks", "DoorDash", "Amazon" ]

# 3 months of transactions
(0..89).each do |days_ago|
  date = days_ago.days.ago.to_date

  # Monthly salary (1st of each month)
  if date.day == 1
    Transaction.create!(
      user: demo, account: bank, finance_category: salary,
      amount_cents: 35_000_00, kind: "income",
      description: "Monthly salary", date: date, occurred_at: date.to_time
    )
  end

  # Daily small expenses (60% chance)
  next unless rand < 0.6

  rand(1..3).times do
    cat = [ groceries, restaurants, transport, bills, entertainment ].sample
    account = [ cash, bank, card ].sample
    amount = rand(15..400) * 100 + rand(0..99)

    Transaction.create!(
      user: demo, account: account, finance_category: cat,
      amount_cents: amount, kind: "expense",
      description: "#{cat.name} — #{vendors.sample}",
      date: date, occurred_at: date.to_time
    )
  end
end

# 5 subscriptions
[
  [ "Netflix",    "Netflix",   89_99,  "monthly", subscriptions_cat ],
  [ "Spotify",    "Spotify",   59_99,  "monthly", subscriptions_cat ],
  [ "iCloud",     "Apple",     29_99,  "monthly", subscriptions_cat ],
  [ "GitHub Pro", "GitHub",     4_00,  "monthly", subscriptions_cat ],
  [ "Domain",     "Namecheap", 250_00, "yearly",  subscriptions_cat ]
].each do |name, vendor, cents, freq, cat|
  next_charge = case freq
  when "weekly"  then Date.current + rand(1..7).days
  when "monthly" then Date.current.beginning_of_month + 1.month + rand(0..15).days
  when "yearly"  then Date.current + rand(30..330).days
  end

  Subscription.create!(
    user: demo, account: bank, finance_category: cat,
    name: name, vendor: vendor, amount_cents: cents,
    frequency: freq, next_charge_on: next_charge,
    start_date: 3.months.ago.to_date, active: true,
    color: "#B8860B"
  )
end

puts "[seed] finance — #{demo.transactions.count} transactions, #{demo.subscriptions.count} subscriptions"
