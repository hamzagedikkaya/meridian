require 'rails_helper'

RSpec.describe "Backups", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /backups" do
    it "renders" do
      get backups_path
      expect(response).to have_http_status(:success)
    end

    it "exposes the latest succeeded backup" do
      create(:backup, user: user, status: "succeeded")
      get backups_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /backups" do
    let(:success_result) { BackupService::Result.new(success?: true,  backup: create(:backup, user: user), error: nil) }
    let(:failure_result) { BackupService::Result.new(success?: false, backup: nil, error: "pg_dump missing") }

    it "redirects with notice on success" do
      allow(BackupService).to receive(:create).and_return(success_result)
      post backups_path, params: { note: "weekly" }
      expect(response).to redirect_to(backups_path)
      expect(flash[:notice]).to be_present
    end

    it "redirects with alert on failure" do
      allow(BackupService).to receive(:create).and_return(failure_result)
      post backups_path
      expect(response).to redirect_to(backups_path)
      expect(flash[:alert]).to be_present
    end
  end

  describe "POST /backups/restore" do
    it "alerts when no file is provided" do
      post restore_backups_path
      expect(response).to redirect_to(backups_path)
      expect(flash[:alert]).to be_present
    end

    it "signs out and redirects on successful restore" do
      file = Rack::Test::UploadedFile.new(StringIO.new("payload"), "application/gzip", original_filename: "backup.tar.gz")
      allow(BackupService).to receive(:restore).and_return(
        BackupService::Result.new(success?: true, backup: nil, error: nil)
      )
      post restore_backups_path, params: { file: file }
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "DELETE /backups/:id" do
    it "destroys the backup" do
      backup = create(:backup, user: user)
      expect { delete backup_path(backup) }.to change(user.backups, :count).by(-1)
    end
  end
end
