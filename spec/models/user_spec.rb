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

  describe "#time_zone" do
    it "returns the user's zone" do
      expect(build(:user, timezone: "Istanbul").time_zone).to eq(ActiveSupport::TimeZone["Istanbul"])
    end

    it "falls back to the app default for a blank or unknown stored name" do
      expect(build(:user, timezone: "Mars/Olympus").time_zone).to eq(Time.zone_default)
      expect(build(:user, timezone: nil).time_zone).to eq(Time.zone_default)
    end
  end

  describe "#preferred_locale" do
    it "returns the user's locale as a symbol" do
      expect(build(:user, locale: "tr").preferred_locale).to eq(:tr)
    end

    it "falls back to the default locale for an unsupported value" do
      expect(build(:user, locale: "de").preferred_locale).to eq(I18n.default_locale)
      expect(build(:user, locale: nil).preferred_locale).to eq(I18n.default_locale)
    end
  end

  describe "#rotate_api_token!" do
    it "stores a new token in place of the old one" do
      user = create(:user)
      old_token = user.api_token

      user.rotate_api_token!

      expect(user.api_token).not_to eq(old_token)
      expect(user.api_token.length).to be >= 24
      expect(user.reload.api_token).to eq(user.api_token)
      expect(described_class.find_by(api_token: old_token)).to be_nil
    end

    it "works on a stored record that fails validation" do
      user = create(:user)
      user.update_column(:timezone, "Mars/Olympus")

      expect { user.rotate_api_token! }.to change { user.reload.api_token }
    end
  end
end
