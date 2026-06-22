require "rails_helper"

RSpec.describe GoalsHelper, type: :helper do
  describe "#goal_deadline_badge" do
    it "returns nil when the goal has no deadline" do
      expect(helper.goal_deadline_badge(build(:goal, deadline: nil))).to be_nil
    end

    it "flags overdue goals in the expense color" do
      badge = helper.goal_deadline_badge(build(:goal, deadline: Date.current - 5))
      expect(badge[:text]).to eq(I18n.t("goals.deadline_overdue", count: 5))
      expect(badge[:class]).to include("expense")
    end

    it "flags a deadline due today" do
      badge = helper.goal_deadline_badge(build(:goal, deadline: Date.current))
      expect(badge[:text]).to eq(I18n.t("goals.deadline_today"))
      expect(badge[:class]).to include("warning")
    end

    it "warns when the deadline is within a week" do
      badge = helper.goal_deadline_badge(build(:goal, deadline: Date.current + 3))
      expect(badge[:text]).to eq(I18n.t("goals.deadline_remaining", count: 3))
      expect(badge[:class]).to include("warning")
    end

    it "stays muted for distant deadlines" do
      badge = helper.goal_deadline_badge(build(:goal, deadline: Date.current + 30))
      expect(badge[:text]).to eq(I18n.t("goals.deadline_remaining", count: 30))
      expect(badge[:class]).to include("fg-muted")
    end
  end
end
