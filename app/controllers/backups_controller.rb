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
      redirect_to backups_path, notice: "Backup created (#{result.backup.display_size})."
    else
      redirect_to backups_path, alert: "Backup failed: #{result.error}"
    end
  end

  def destroy
    @backup.destroy
    redirect_to backups_path, notice: "Backup deleted."
  end

  def download
    redirect_to rails_blob_url(@backup.archive, disposition: "attachment")
  end

  def restore
    if params[:file].blank?
      redirect_to backups_path, alert: "Choose a backup file first." and return
    end

    result = BackupService.restore(params[:file])
    if result.success?
      sign_out current_user
      redirect_to new_user_session_path, notice: "Restore complete. Sign in with the restored credentials."
    else
      redirect_to backups_path, alert: "Restore failed: #{result.error}"
    end
  end

  private

  def set_backup
    @backup = current_user.backups.find(params[:id])
  end
end
