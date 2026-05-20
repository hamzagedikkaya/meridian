# Changelog

All notable changes to Meridian are documented here. Format roughly follows [Keep a Changelog](https://keepachangelog.com/).

## [1.0.0] — 2026-05-20

Initial release of Meridian as a self-hosted personal life OS.

### Added

- Rails 8 application shell with Hotwire (Turbo + Stimulus), Importmap, Tailwind v4
- ViewComponent + Lookbook (`/lookbook` in dev) for layout and UI primitives
- Dark-first design system with Fraunces (Google Fonts) display serif + DM Sans body
- Devise authentication with custom profile fields (name, timezone, currency, locale, theme, weekly review day) and avatar upload
- Multi-tab Settings page (Profile, Preferences, Data, Notifications)
- **Finance** module: accounts, categories, transactions (income/expense/transfer), subscriptions, transfers, dashboards, reports with charts, and CSV export
- **Todos** module: lists, priorities, statuses, due dates, filter tabs (Open/Today/This week/Overdue/Done)
- **Habits** module: daily/weekly/monthly tracking, streak calculation, 12-week heatmap, completion rate
- **Calendar** module: monthly grid view with todos + subscriptions overlay, iCal export feed
- **Journal** module: ActionText rich body, mood emoji, energy level, gratitude, tags, timeline view
- **Goals** module: financial/habit/custom targets with auto-calculated progress
- **Backup & Restore**: `pg_dump` custom format + ActiveStorage blobs packed as `.tar.gz` with schema versioning and one-click restore
- **Dashboard**: bento grid with hero stats, today's habits, upcoming todos, today's events, finance sparkline, goals progress, journal CTA
- **Global Search**: `⌘K` / `/` modal with multi-model ILIKE search and arrow-key navigation
- **Universal Tags**: polymorphic Tag + Tagging models linkable to transactions, todos, journal, events, goals
- **Quick Capture**: floating action button + `c` shortcut + rule-based router (numbers → transaction, `habit:` → log, text → todo)
- **Weekly Review**: guided form with summarized week stats and 3 reflection prompts
- **Focus Timer**: Pomodoro Stimulus controller with browser notification and per-todo time tracking
- **Insights**: cross-module patterns (weekend vs weekday spending, habit streaks, mood × habit correlation, focus by weekday, top categories, weekly todo trend)
- Light mode toggle (system / dark / light) persisted to localStorage
- Vim-style `g <letter>` keyboard navigation
- iCal calendar feed at `/calendar/feed`
- Seed data: 2 users + 97 transactions + 5 subscriptions + 10 todos + 6 habits + 360 habit logs + 8 events + 6 journal entries + 4 goals
- RSpec specs covering models, requests, and services
- RuboCop (rails-omakase + rspec) and Brakeman security scan with documented ignores for safe Open3-array pg_dump/pg_restore calls
