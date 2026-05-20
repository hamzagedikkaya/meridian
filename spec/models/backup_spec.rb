require 'rails_helper'

RSpec.describe Backup, type: :model do
  describe "validations" do
    subject { create(:user).backups.build(status: "pending") }

    it { is_expected.to validate_inclusion_of(:status).in_array(described_class::STATUSES) }
  end

  describe "#display_size" do
    let(:user) { create(:user) }

    it "formats bytes" do
      b = user.backups.build(status: "succeeded", size_bytes: 500)
      expect(b.display_size).to eq("500.0 B")
    end

    it "formats megabytes" do
      b = user.backups.build(status: "succeeded", size_bytes: 5 * 1024 * 1024)
      expect(b.display_size).to eq("5.0 MB")
    end
  end
end
