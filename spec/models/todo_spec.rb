require 'rails_helper'

RSpec.describe Todo, type: :model do
  describe "validations" do
    subject { build(:todo) }

    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_inclusion_of(:priority).in_array(described_class::PRIORITIES) }
    it { is_expected.to validate_inclusion_of(:status).in_array(described_class::STATUSES) }
  end

  describe "#overdue?" do
    it "is true when due_at is past and not done" do
      t = build(:todo, due_at: 1.day.ago, status: "pending")
      expect(t).to be_overdue
    end

    it "is false when done" do
      t = build(:todo, due_at: 1.day.ago, status: "done")
      expect(t).not_to be_overdue
    end
  end

  describe "completed_at sync" do
    it "sets completed_at when marked done" do
      t = create(:todo, status: "pending")
      expect { t.update(status: "done") }.to change { t.completed_at }.from(nil)
    end

    it "clears completed_at when reopened" do
      t = create(:todo, status: "done")
      expect { t.update(status: "pending") }.to change { t.completed_at }.to(nil)
    end
  end
end
