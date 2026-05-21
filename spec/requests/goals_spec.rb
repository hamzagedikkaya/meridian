require 'rails_helper'

RSpec.describe "Goals", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /goals" do
    it "renders" do
      get goals_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /goals" do
    it "creates a goal" do
      expect {
        post goals_path, params: { goal: { name: "Save", target_type: "custom", target_value: 100, unit: "TRY", status: "active" } }
      }.to change(Goal, :count).by(1)
    end

    it "links a related account when target_type is financial" do
      account = create(:account, user: user)
      post goals_path, params: { goal: { name: "Save 5K", target_type: "financial", target_value: 5000, status: "active", related: "Account-#{account.id}" } }
      expect(Goal.last.related).to eq(account)
    end

    it "links a related habit when target_type is habit" do
      habit = create(:habit, user: user, name: "Read")
      post goals_path, params: { goal: { name: "100 days reading", target_type: "habit", target_value: 100, status: "active", related: "Habit-#{habit.id}" } }
      expect(Goal.last.related).to eq(habit)
    end
  end

  describe "PATCH /goals/:id/update_progress" do
    let(:goal) { create(:goal, user: user, target_type: "custom", target_value: 100, current_value: 5) }

    it "sets current_value when current_value param given" do
      patch update_progress_goal_path(goal), params: { current_value: 25 }
      expect(goal.reload.current_value.to_f).to eq(25.0)
    end

    it "increments by delta when delta param given" do
      patch update_progress_goal_path(goal), params: { delta: 3 }
      expect(goal.reload.current_value.to_f).to eq(8.0)
    end

    it "supports negative delta but clamps at zero" do
      patch update_progress_goal_path(goal), params: { delta: -10 }
      expect(goal.reload.current_value.to_f).to eq(0.0)
    end

    it "marks the goal achieved when value reaches target" do
      patch update_progress_goal_path(goal), params: { current_value: 100 }
      expect(goal.reload.status).to eq("achieved")
    end
  end
end
