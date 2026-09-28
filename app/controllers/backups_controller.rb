class BackupsController < ApplicationController
  before_action :set_backup, only: [ :show, :destroy, :download ]

  def index
    @backups = current_user.backups.recent
    @last_succeeded = @backups.succeeded.first
  end

  def show
  end

  def create
    result = BackupService.create(current_user, note: params[:note])
    if result.success?
      redirect_to backups_path, notice: t("backups.create_success", size: result.backup.display_size, default: "Backup created (%{size}).")
    else
      redirect_to backups_path, alert: t("backups.create_failed", error: result.error, default: "Backup failed: %{error}")
    end
  end

  def destroy
    @backup.destroy
    redirect_to backups_path, notice: t("flash.deleted")
  end

  def download
    # rails_blob_url hands out a URL that ActiveStorage serves with no
    # authentication at all — possession of the link is the only credential, and
    # with urls_expire_in unset it never stopped working. The archive is a full
    # pg_dump of every user's rows, api_token column included, so it is streamed
    # from here instead, behind the session.
    return head :not_found unless @backup.archive.attached?

    send_data @backup.archive.download,
              filename: @backup.archive.filename.to_s,
              type: @backup.archive.content_type || "application/gzip",
              disposition: "attachment"
  end

  def restore
    if params[:file].blank?
      redirect_to backups_path, alert: t("backups.choose_file", default: "Choose a backup file first.") and return
    end

    # Restore runs pg_restore --clean against the live database from a file the
    # caller supplied. That is the single most destructive action in the app, so
    # it is re-authenticated rather than relying on the session alone.
    unless current_user.valid_password?(params[:current_password].to_s)
      redirect_to backups_path, alert: t("backups.restore_password_wrong", default: "Wrong password — restore cancelled.") and return
    end

    result = BackupService.restore(params[:file])
    if result.success?
      sign_out current_user
      redirect_to new_user_session_path, notice: t("backups.restore_complete", default: "Restore complete. Sign in with the restored credentials.")
    else
      redirect_to backups_path, alert: t("backups.restore_failed", error: result.error, default: "Restore failed: %{error}")
    end
  end

  private

  def set_backup
    @backup = current_user.backups.find(params[:id])
  end
end
