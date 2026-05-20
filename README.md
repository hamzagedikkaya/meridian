# 🌅 Meridian

> *Your life, beautifully organized.*

Meridian is a self-hosted, local-first personal life OS built with Rails 8. It bundles **finance tracking, todos, habits, calendar, journal, goals, weekly reviews, and pomodoro focus sessions** into a single dark-first Hotwire app — with full backup and restore so you can move your data between machines.

---

## ✨ Features

- 💰 **Finance** — accounts, categories, transactions, transfers, subscriptions, 6-month trends, CSV export
- ✅ **Todos** — lists, priorities, due dates, today/week/overdue filters
- 🔥 **Habits** — daily/weekly tracking, streaks, 12-week heatmap, completion rates
- 📅 **Calendar** — monthly grid with todos and subscriptions overlay, iCal feed
- 📓 **Journal** — rich text entries with mood emoji, energy, gratitude, tags
- 🎯 **Goals** — financial/habit/custom targets with auto-calculated progress
- 💾 **Backup & Restore** — full `pg_dump` + ActiveStorage archive as `.tar.gz`
- 🏠 **Dashboard** — bento grid widgets, quick stats, today's overview
- 🔍 **Global Search** — `⌘K` / `/` instant search across every module
- ⚡ **Quick Capture** — `c` shortcut, FAB, smart router (numbers → transaction, "habit:" → log, text → todo)
- 📊 **Weekly Review** — guided reflection with auto-summarized stats
- 🍅 **Focus Timer** — pomodoro with browser notifications and time tracking
- 📈 **Insights** — cross-module patterns: weekend vs weekday spending, mood × habit correlation, focus by weekday
- ⌨️ **Keyboard shortcuts** — vim-style `g d/f/t/h/c/j/g` to navigate
- 🎨 **Design** — Fraunces + DM Sans, dark-first amber/gold palette, light mode toggle

## 🧰 Tech Stack

| Layer | Tech |
|-------|------|
| Backend | Ruby 3.3 + Rails 8 |
| Frontend | Hotwire (Turbo + Stimulus), Importmap, Tailwind v4 |
| DB | PostgreSQL 14+ |
| Auth | Devise |
| Charts | Chartkick + Chart.js + groupdate |
| Money | money-rails |
| Recurring | ice_cube |
| Backup | pg_dump + tar.gz + ActiveStorage |
| Testing | RSpec + FactoryBot + Shoulda + Capybara + SimpleCov |
| Lint/Security | RuboCop (omakase + rspec) + Brakeman |

## 🚀 Local Setup

### Requirements

- Ruby 3.3.x (managed via `rbenv` or `asdf`)
- PostgreSQL 14+ running locally
- Node.js 22+ (only for native Tailwind binary)

### Install

```bash
git clone <your-repo> meridian
cd meridian
bundle install
bin/rails db:create db:migrate db:seed
```

The seed creates two users:
- `admin@meridian.local` / `password123`
- `demo@meridian.local` / `demo12345` (pre-populated with sample data)

### Run

```bash
bin/dev          # starts Tailwind watcher + Rails server (recommended)
# or
bin/rails server # just the server (run `bin/rails tailwindcss:build` first if styles look off)
```

Then open http://localhost:3000.

### Tests & Lint

```bash
bin/rspec
bundle exec rubocop
bundle exec brakeman -i config/brakeman.ignore
```

## 💾 Backup & Restore

### Create a backup

1. Navigate to **Settings → Data → Backups** or just `/backups`.
2. Click **Create backup**.
3. Download the resulting `.tar.gz` from the list.

The archive contains:
- `db.dump` — full PostgreSQL dump (custom format)
- `storage/` — all ActiveStorage blobs (avatars, journal attachments)
- `metadata.json` — Meridian + schema version, timestamp

### Restore on another machine

1. Set up Meridian on the new machine using **Local Setup** above.
2. Go to `/backups` → **Restore** card.
3. Upload your `.tar.gz` file and confirm.
4. The app signs you out — sign in with your original credentials.

⚠️ **Restore wipes the current database.** Take a fresh backup first if needed.

## ⌨️ Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘K` / `Ctrl+K` / `/` | Open global search |
| `c` | Open quick capture |
| `g d` | Dashboard |
| `g f` | Finance |
| `g t` | Todos |
| `g h` | Habits |
| `g c` | Calendar |
| `g j` | Journal |
| `g g` | Goals |
| `Esc` | Close modals |

## 📂 Module Map

```
Dashboard (/)
├── Finance (/finance)
│   ├── Transactions, Accounts, Categories, Subscriptions
│   ├── Transfers, Reports, CSV export
├── Todos (/todos), TodoLists (/todo_lists)
├── Habits (/habits)
├── Calendar (/calendar) + iCal feed (/calendar/feed)
├── Journal (/journal)
├── Goals (/goals)
├── Insights (/insights)
├── Weekly Reviews (/weekly_reviews)
├── Backups (/backups)
└── Settings (/settings)
```

## 🤝 License

Personal use. Not licensed for redistribution.

---

*Meridian — Your life, beautifully organized.*
