require 'rails_helper'

RSpec.describe User, type: :model do
  describe "factory" do
    it "is valid" do
      expect(build(:user)).to be_valid
    end
  end

  describe "validations" do
    subject { build(:user) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(80) }
    it { is_expected.to validate_presence_of(:timezone) }
    it { is_expected.to validate_presence_of(:currency) }
    it { is_expected.to validate_length_of(:currency).is_equal_to(3) }
    it { is_expected.to validate_inclusion_of(:locale).in_array(%w[tr en]) }
    it { is_expected.to validate_inclusion_of(:theme_preference).in_array(%w[dark light system]) }
    it { is_expected.to validate_inclusion_of(:weekly_review_day).in_range(0..6) }

    it "rejects an unknown timezone" do
      user = build(:user, timezone: "Mars/Olympus")
      expect(user).not_to be_valid
      expect(user.errors[:timezone]).to be_present
    end
  end

  describe "#display_name" do
    it "returns name when present" do
      user = build(:user, name: "Hamza")
      expect(user.display_name).to eq("Hamza")
    end

    it "falls back to email local-part when name blank" do
      user = build(:user, name: "", email: "test@example.com")
      expect(user.display_name).to eq("test")
    end
  end

  describe "#initials" do
    it "returns up to two uppercase initials" do
      expect(build(:user, name: "Hamza Gedikkaya").initials).to eq("HG")
    end

    it "returns a single initial for one-word names" do
      expect(build(:user, name: "Meridian").initials).to eq("M")
    end
  end
end
