<p align="center"><sub><b>English</b> · <a href="README.tr.md">Türkçe</a></sub></p>

<h1 align="center">
  <img src="public/icon.svg" alt="" width="44" valign="middle" />
  &nbsp;Meridian
</h1>

<p align="center"><i>Your life, beautifully organized.</i></p>

<p align="center">
  <a href="#-quick-start">Quick start</a> ·
  <a href="#-features">Features</a> ·
  <a href="#-backup--restore">Backup</a> ·
  <a href="#-keyboard-shortcuts">Shortcuts</a>
</p>

---

Meridian is a self-hosted, local-first personal life OS. One Rails app gathers the things that usually scatter across half a dozen subscriptions — money, habits, todos, calendar, journal, goals — and keeps them on a machine you control. Backups are a single `tar.gz`, so moving your data is a copy-paste away.

<p align="center">
  <img src="docs/dashboard.png" alt="Dashboard" width="100%" />
</p>

## ✨ Features

- 💰 **Finance** — accounts, categories, transactions, subscriptions, 6-month trends, CSV export
- ✅ **Todos** — lists, priorities, due dates, today / week / overdue filters
- 🔥 **Habits** — daily and weekly cadences, streaks, 12-week heatmap, completion rates
- 📅 **Calendar** — monthly grid plus drag-to-reschedule weekly view, iCal feed
- 📓 **Journal** — rich-text entries with mood, energy, gratitude, and tags
- 🎯 **Goals** — financial / habit / custom targets with live-calculated progress
- 🏠 **Dashboard** — bento-grid widgets that surface today's habits, todos, events, and spend
- 🔍 **Global search** — `⌘K` instant search across every module
- ⚡ **Quick capture** — one input, smart router: numbers become transactions, `habit:` becomes a log, freeform becomes a todo
- 📊 **Weekly review** — guided reflection with auto-summarised stats
- 🍅 **Focus timer** — pomodoro with browser notifications and per-todo time tracking
- 📈 **Insights** — cross-module patterns: weekday vs weekend spending, mood × habit correlation, most productive day
- 💾 **Backup & restore** — `pg_dump` + ActiveStorage blobs bundled into a portable archive
- 🎨 **Design** — Fraunces + DM Sans, dark-first amber/gold palette, optional light mode

## 🧰 Tech Stack

| Layer | Tech |
|---|---|
| Backend | Ruby 3.3 · Rails 8 |
| Frontend | Hotwire (Turbo + Stimulus), Importmap, Tailwind v4 |
| Database | PostgreSQL 14+ |
| Auth | Devise |
| Charts | Chartkick · Chart.js · groupdate |
| Money | money-rails |
| Recurring rules | ice_cube |
| Backup | pg_dump · tar.gz · ActiveStorage |
| Testing | RSpec · FactoryBot · Shoulda · Capybara · SimpleCov |
| Lint / security | RuboCop (omakase + rspec) · Brakeman |

## 🚀 Quick Start

**Requirements** — Ruby 3.3.x (via `rbenv` / `asdf`), PostgreSQL 14+, Node.js 22+ (only used for the native Tailwind binary).

```bash
git clone <your-repo> meridian
cd meridian
bundle install
bin/rails db:create db:migrate db:seed
bin/dev
```

Open <http://localhost:3000>. The seed creates two accounts:

- `admin@meridian.local` / `password123`
- `demo@meridian.local` / `demo12345` — pre-populated with habits, goals, transactions, and journal entries

### Tests, lint, security

```bash
bin/rspec
bundle exec rubocop
bundle exec brakeman -i config/brakeman.ignore
```

## 💾 Backup & Restore

Backups are first-class: everything that defines "your Meridian" — schema, rows, attachments, app version — lives in a single archive.

**Create**

1. Open **Settings → Data**, or go straight to `/backups`.
2. Click **Create backup**.
3. Download the resulting `.tar.gz` from the list.

The archive contains:

- `db.dump` — full PostgreSQL dump (custom format)
- `storage/` — every ActiveStorage blob (avatars, journal attachments)
- `metadata.json` — Meridian version, schema version, timestamp

**Restore** — on the new machine, set up Meridian with the steps above, visit `/backups`, drop the archive into **Restore**, confirm. The app signs you out; sign back in with your original credentials.

> ⚠️ Restoring wipes the current database. Take a fresh backup first if there's anything you want to keep.

Full archive layout in [docs/backup_format.md](docs/backup_format.md).

## ⌨️ Keyboard Shortcuts

| | |
|---|---|
| `⌘K` / `Ctrl+K` / `/` | Global search |
| `c` | Quick capture |
| `g d` · `g f` · `g t` · `g h` | Dashboard · Finance · Todos · Habits |
| `g c` · `g j` · `g g` | Calendar · Journal · Goals |
| `Esc` | Close any modal |

## 📂 Module Map

```
Dashboard       (/)
├─ Finance      (/finance)
│  ├─ Transactions, Accounts, Categories, Subscriptions
│  └─ Reports, CSV export
├─ Todos        (/todos), Todo lists (/todo_lists)
├─ Habits       (/habits)
├─ Calendar     (/calendar) — month + week, iCal feed at /calendar/feed
├─ Journal      (/journal)
├─ Goals        (/goals)
├─ Insights     (/insights)
├─ Weekly review (/weekly_reviews)
├─ Backups      (/backups)
└─ Settings     (/settings)
```

## 📄 License

Meridian is released under the [**PolyForm Noncommercial License 1.0.0**](LICENSE). Personal, research, educational, and other noncommercial use is free; commercial use is not granted by this license. Open an issue if you'd like to discuss a separate arrangement.

---

<p align="center"><sub>Meridian — your life, beautifully organized.</sub></p>
