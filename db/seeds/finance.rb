# Finance seed — runs against the demo user.
# Creates accounts, categories, ~12 months of varied transactions, subscriptions.

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
cash = demo.accounts.create!(name: "Cüzdan",       account_type: "cash",        currency: "TRY", initial_balance_cents:    200_00, color: "#D4A574")
bank = demo.accounts.create!(name: "Maaş hesabı",  account_type: "bank",        currency: "TRY", initial_balance_cents:  8_500_00, color: "#6B8FA0")
card = demo.accounts.create!(name: "Kredi kartı",  account_type: "credit_card", currency: "TRY", initial_balance_cents:         0, color: "#B85450")
save = demo.accounts.create!(name: "Birikim",      account_type: "savings",     currency: "TRY", initial_balance_cents: 25_000_00, color: "#6B8E5A")
gold = demo.accounts.create!(name: "Altın",        account_type: "savings",     currency: "GAU", initial_balance_cents:        12, color: "#B8860B")

# Income categories
salary    = demo.finance_categories.create!(name: "Maaş",      kind: "income", color: "#6B8E5A")
freelance = demo.finance_categories.create!(name: "Serbest iş", kind: "income", color: "#D4A574")
gifts_in  = demo.finance_categories.create!(name: "Hediye",     kind: "income", color: "#B8860B")

# Expense categories — broader variety so the pie chart has color/visual interest
groceries     = demo.finance_categories.create!(name: "Market",        kind: "expense", color: "#D4915A")
restaurants   = demo.finance_categories.create!(name: "Restoran",      kind: "expense", color: "#B85450")
transport     = demo.finance_categories.create!(name: "Ulaşım",        kind: "expense", color: "#6B8FA0")
bills         = demo.finance_categories.create!(name: "Faturalar",     kind: "expense", color: "#A09B8E")
subs_cat      = demo.finance_categories.create!(name: "Abonelikler",   kind: "expense", color: "#B8860B")
entertainment = demo.finance_categories.create!(name: "Eğlence",       kind: "expense", color: "#8B5A00")
clothing      = demo.finance_categories.create!(name: "Giyim",         kind: "expense", color: "#7A5C9E")
health        = demo.finance_categories.create!(name: "Sağlık",        kind: "expense", color: "#5A9E8B")
investment    = demo.finance_categories.create!(name: "Yatırım",       kind: "expense", color: "#C9A227")

vendors_by_cat = {
  groceries     => [ "Migros", "Şok", "A101", "BİM", "Carrefour" ],
  restaurants   => [ "Köşe", "Lokanta", "Burger King", "Starbucks", "Karaköy Lokantası" ],
  transport     => [ "İBB", "Uber", "Bolt", "BiTaksi", "Shell" ],
  bills         => [ "TEDAŞ", "İGDAŞ", "Vodafone", "İSKİ", "Turkcell" ],
  entertainment => [ "Cinemaximum", "Spotify Live", "Konser", "Steam" ],
  clothing      => [ "Mavi", "LCW", "Zara", "Boyner" ],
  health        => [ "Eczane", "Diş hekimi", "Spor salonu" ]
}

# Generate 365 days of transactions, with realistic patterns:
# - Monthly salary on the 1st (35-40k)
# - Occasional freelance income (~12% of days)
# - Daily expenses (70% of days) across the broader category mix
# - Monthly gold purchase on the 15th (~1-2 grams)
(0..364).each do |days_ago|
  date = days_ago.days.ago.to_date

  if date.day == 1
    Transaction.create!(
      user: demo, account: bank, finance_category: salary,
      amount_cents: rand(35_000..40_000) * 100, kind: "income",
      description: "Aylık maaş", date: date, occurred_at: date.to_time
    )
  end

  if rand < 0.12
    Transaction.create!(
      user: demo, account: bank, finance_category: freelance,
      amount_cents: rand(2_000..8_000) * 100, kind: "income",
      description: [ "Danışmanlık", "Proje teslimi", "Tasarım işi" ].sample,
      date: date, occurred_at: date.to_time
    )
  end

  # Monthly investment (cash → savings transfer modelled as a paired expense/income)
  if date.day == 15
    grams = rand(1..2)
    Transaction.create!(
      user: demo, account: gold,
      amount_cents: grams, kind: "income",
      description: "#{grams} gr altın alımı", date: date, occurred_at: date.to_time
    )
    Transaction.create!(
      user: demo, account: bank, finance_category: investment,
      amount_cents: grams * 3_200_00, kind: "expense",
      description: "#{grams} gr altın alımı (TRY karşılığı)", date: date, occurred_at: date.to_time
    )
  end

  next unless rand < 0.7

  rand(1..3).times do
    cat = [ groceries, groceries, restaurants, transport, bills, entertainment, clothing, health ].sample
    account = [ cash, bank, bank, card ].sample
    amount = case cat
    when groceries     then rand(40..600)
    when restaurants   then rand(80..800)
    when transport     then rand(20..300)
    when bills         then rand(200..1500)
    when entertainment then rand(50..600)
    when clothing      then rand(150..2500)
    when health        then rand(100..1500)
    else rand(20..500)
    end
    vendor = (vendors_by_cat[cat] || [ "Diğer" ]).sample

    Transaction.create!(
      user: demo, account: account, finance_category: cat,
      amount_cents: amount * 100 + rand(0..99), kind: "expense",
      description: "#{cat.name} — #{vendor}",
      date: date, occurred_at: date.to_time
    )
  end
end

# Subscriptions
[
  [ "Netflix",       "Netflix",   189_99,  "monthly", subs_cat ],
  [ "Spotify",       "Spotify",    59_99,  "monthly", subs_cat ],
  [ "iCloud+ 200GB", "Apple",      29_99,  "monthly", subs_cat ],
  [ "GitHub Pro",    "GitHub",      4_00,  "monthly", subs_cat ],
  [ "Domain",        "Namecheap", 250_00,  "yearly",  subs_cat ],
  [ "Spor salonu",   "MaxiFit",   450_00,  "monthly", health ]
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
    start_date: 12.months.ago.to_date, active: true,
    color: cat.color
  )
end

puts "[seed] finance — #{demo.transactions.count} transactions, #{demo.subscriptions.count} subscriptions, #{demo.accounts.count} accounts"
