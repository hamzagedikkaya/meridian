# Meridian Backup Format

A Meridian backup is a `.tar.gz` archive with this structure:

```
meridian-backup-YYYYMMDD-HHMMSS/
├── metadata.json
├── db.dump
└── storage/
    └── <ActiveStorage blob tree>
```

## `metadata.json`

```json
{
  "meridian_version": "1.0.0",
  "schema_version": "20260520163330",
  "created_at": "2026-05-20T18:45:00+03:00",
  "user_id": 1,
  "user_email": "admin@meridian.local"
}
```

The `schema_version` is `ActiveRecord::Migrator.current_version` at backup time. Restore refuses to proceed if it doesn't match the current schema, so always upgrade the destination Meridian to the same schema first.

## `db.dump`

PostgreSQL custom-format dump produced by:

```bash
pg_dump --format=custom --no-owner --no-acl --file=db.dump --dbname=<db>
```

Restored with:

```bash
pg_restore --clean --if-exists --no-owner --no-acl --dbname=<db> db.dump
```

## `storage/`

Mirror of `Rails.root/storage/`. Contains the local-disk ActiveStorage tree (avatars, journal attachments, previous backup archives). Restore replaces the live `storage/` directory atomically.

## What's NOT in a backup

- `config/master.key` — copy that manually (or regenerate credentials on the destination).
- Solid Queue/Cache/Cable internal state (it's per-installation, regenerates on first run).
- `tmp/`, `log/`, gem cache.

## Multi-user note

Backups capture the *entire database*, not just one user's rows. Currently Meridian is built for single-user local use; if you ever introduce multi-tenancy, the BackupService needs to switch to per-user `pg_dump --data-only --table=...` exports.
