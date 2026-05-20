require 'rails_helper'

RSpec.describe Tag, type: :model do
  describe "validations" do
    subject { build(:tag) }

    it { is_expected.to validate_presence_of(:name) }
  end

  describe "uniqueness" do
    it "rejects duplicate slug within the same user" do
      user = create(:user)
      create(:tag, user: user, name: "Work")
      duplicate = build(:tag, user: user, name: "Work")
      expect(duplicate).not_to be_valid
    end
  end

  describe "slug generation" do
    it "parameterizes the name into a slug" do
      tag = build(:tag, name: "My Work Tag")
      tag.valid?
      expect(tag.slug).to eq("my-work-tag")
    end
  end
end
