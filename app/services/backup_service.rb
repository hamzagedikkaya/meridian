require "fileutils"
require "open3"
require "json"
require "tempfile"

# Creates and restores Meridian backups.
#
# Backup archive layout (.tar.gz):
#   meridian-backup-<timestamp>/
#     metadata.json   — version + schema version + created_at
#     db.dump         — pg_dump --format=custom
#     storage/        — ActiveStorage blobs (mirrored from local disk)
#
# Backups are global — a backup contains the entire database, not just one user's
# rows. Multi-user Meridian deployments would need a per-user export instead.
class BackupService
  Result = Struct.new(:success?, :backup, :error, keyword_init: true)

  def self.create(user, note: nil)
    new(user).create(note: note)
  end

  def self.restore(file)
    new(nil).restore(file)
  end

  def initialize(user)
    @user = user
  end

  def create(note: nil)
    backup = @user.backups.create!(status: "running", note: note, meridian_version: Backup::MERIDIAN_VERSION, schema_version: schema_version)

    Dir.mktmpdir("meridian-backup-#{Time.now.to_i}") do |workdir|
      dump_path = File.join(workdir, "db.dump")
      storage_path = File.join(workdir, "storage")
      meta_path  = File.join(workdir, "metadata.json")

      # 1. pg_dump
      db = ActiveRecord::Base.connection_db_config.configuration_hash
      cmd = [
        "pg_dump",
        "--format=custom",
        "--no-owner",
        "--no-acl",
        "--file=#{dump_path}",
        "--dbname=#{db[:database]}"
      ]
      cmd += [ "--host=#{db[:host]}" ] if db[:host]
      cmd += [ "--port=#{db[:port]}" ] if db[:port]
      cmd += [ "--username=#{db[:username]}" ] if db[:username]

      env = db[:password] ? { "PGPASSWORD" => db[:password] } : {}
      _stdout, stderr, status = Open3.capture3(env, *cmd)
      raise "pg_dump failed: #{stderr}" unless status.success?

      # 2. Copy ActiveStorage blobs (skip our own backup attachments to avoid recursion)
      blobs_root = Rails.root.join("storage").to_s
      if File.directory?(blobs_root)
        FileUtils.mkdir_p(storage_path)
        FileUtils.cp_r(Dir.glob("#{blobs_root}/*"), storage_path)
      end

      # 3. Metadata
      File.write(meta_path, JSON.pretty_generate(
        meridian_version: Backup::MERIDIAN_VERSION,
        schema_version: schema_version,
        created_at: Time.current.iso8601,
        user_id: @user.id,
        user_email: @user.email
      ))

      # 4. Pack into tar.gz
      filename = "meridian-backup-#{Time.current.strftime('%Y%m%d-%H%M%S')}.tar.gz"
      archive_path = File.join(Dir.tmpdir, filename)
      Dir.chdir(workdir) do
        system("tar", "-czf", archive_path, ".") || raise("tar failed")
      end

      size = File.size(archive_path)
      backup.archive.attach(
        io: File.open(archive_path),
        filename: filename,
        content_type: "application/gzip"
      )
      backup.update!(status: "succeeded", filename: filename, size_bytes: size)
      File.delete(archive_path) if File.exist?(archive_path)
    end

    Result.new(success?: true, backup: backup)
  rescue StandardError => e
    backup&.update(status: "failed", error_message: e.message)
    Result.new(success?: false, backup: backup, error: e.message)
  end

  def restore(uploaded_file)
    Dir.mktmpdir("meridian-restore-#{Time.now.to_i}") do |workdir|
      # 1. Extract
      archive = File.join(workdir, "archive.tar.gz")
      File.binwrite(archive, uploaded_file.read)
      Dir.chdir(workdir) { system("tar", "-xzf", archive) || raise("tar extract failed") }

      meta = JSON.parse(File.read(File.join(workdir, "metadata.json")))
      raise "Schema version mismatch: backup is #{meta['schema_version']} but DB is #{schema_version}" if meta["schema_version"] && meta["schema_version"] != schema_version

      # 2. Restore DB
      db = ActiveRecord::Base.connection_db_config.configuration_hash
      env = db[:password] ? { "PGPASSWORD" => db[:password] } : {}
      cmd = [
        "pg_restore",
        "--clean",
        "--if-exists",
        "--no-owner",
        "--no-acl",
        "--dbname=#{db[:database]}",
        File.join(workdir, "db.dump")
      ]
      cmd += [ "--host=#{db[:host]}" ] if db[:host]
      cmd += [ "--port=#{db[:port]}" ] if db[:port]
      cmd += [ "--username=#{db[:username]}" ] if db[:username]

      # pg_restore returns non-zero on warnings; we tolerate that and check for fatal errors
      _stdout, stderr, _status = Open3.capture3(env, *cmd)
      raise "pg_restore failed: #{stderr}" if stderr =~ /FATAL|connection to/

      # 3. Restore ActiveStorage blobs
      restored_storage = File.join(workdir, "storage")
      if File.directory?(restored_storage)
        FileUtils.rm_rf(Rails.root.join("storage").to_s)
        FileUtils.mkdir_p(Rails.root.join("storage").to_s)
        FileUtils.cp_r(Dir.glob("#{restored_storage}/*"), Rails.root.join("storage").to_s)
      end
    end

    Result.new(success?: true)
  rescue StandardError => e
    Result.new(success?: false, error: e.message)
  end

  private

  def schema_version
    ActiveRecord::Migrator.current_version.to_s
  end
end
