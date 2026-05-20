require 'rails_helper'

RSpec.describe BackupService do
  let(:user) { create(:user) }

  describe ".create" do
    it "creates a backup record and a tar.gz attachment", :slow do
      result = described_class.create(user, note: "Test backup")
      expect(result.success?).to be true
      expect(result.backup.status).to eq("succeeded")
      expect(result.backup.archive).to be_attached
      expect(result.backup.size_bytes).to be > 0
    end
  end
end
