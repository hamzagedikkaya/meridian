require 'rails_helper'

RSpec.describe WeeklyReview, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user) }
  end

  describe "validations" do
    subject { build(:weekly_review) }

    it { is_expected.to validate_presence_of(:week_starting) }
  end

  describe "uniqueness" do
    it "prevents two reviews for the same user and week" do
      user = create(:user)
      week = Date.current.beginning_of_week
      create(:weekly_review, user: user, week_starting: week)
      dup = build(:weekly_review, user: user, week_starting: week)
      expect(dup).not_to be_valid
      expect(dup.errors[:week_starting]).to be_present
    end

    it "allows two reviews for different users in the same week" do
      week = Date.current.beginning_of_week
      create(:weekly_review, user: create(:user), week_starting: week)
      second = build(:weekly_review, user: create(:user), week_starting: week)
      expect(second).to be_valid
    end
  end

  describe "#completed?" do
    it "is true when completed_at is set" do
      review = build(:weekly_review, completed_at: Time.current)
      expect(review).to be_completed
    end

    it "is false when completed_at is nil" do
      review = build(:weekly_review, completed_at: nil)
      expect(review).not_to be_completed
    end
  end

  describe "#week_end" do
    it "is 6 days after the start" do
      review = build(:weekly_review, week_starting: Date.new(2026, 5, 4))
      expect(review.week_end).to eq(Date.new(2026, 5, 10))
    end
  end

  describe "scopes" do
    let(:user) { create(:user) }

    it ".completed only returns reviews with completed_at" do
      done    = create(:weekly_review, user: user, week_starting: Date.current.beginning_of_week - 7.days, completed_at: Time.current)
      _draft  = create(:weekly_review, user: user, week_starting: Date.current.beginning_of_week, completed_at: nil)
      expect(described_class.completed).to include(done)
      expect(described_class.completed.count).to eq(1)
    end
  end
end
