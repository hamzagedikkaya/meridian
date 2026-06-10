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

  # --- Added coverage below ---

  describe "GET /goals (index recalculation)" do
    it "recalculates active financial goals against the linked account balance" do
      account = create(:account, user: user, initial_balance_cents: 750_00)
      goal = create(:goal, user: user, target_type: "financial", target_value: 1000, current_value: 0, status: "active", related: account)

      get goals_path

      expect(response).to have_http_status(:success)
      expect(goal.reload.current_value.to_f).to eq(750.0)
    end
  end

  describe "GET /goals/new" do
    it "renders the new form" do
      get new_goal_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /goals/:id" do
    it "renders a custom goal and refreshes its progress" do
      goal = create(:goal, user: user, target_type: "custom")
      get goal_path(goal)
      expect(response).to have_http_status(:success)
    end

    it "renders a financial goal and exposes linkable accounts" do
      create(:account, user: user)
      goal = create(:goal, user: user, target_type: "financial", target_value: 1000)
      get goal_path(goal)
      expect(response).to have_http_status(:success)
    end

    it "renders a habit goal and exposes linkable habits" do
      create(:habit, user: user)
      goal = create(:goal, user: user, target_type: "habit", target_value: 30)
      get goal_path(goal)
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /goals (related param branches)" do
    it "leaves related nil when related is 'none'" do
      post goals_path, params: { goal: { name: "No link", target_type: "custom", target_value: 10, status: "active", related: "none" } }
      expect(Goal.last.related).to be_nil
    end

    it "renders new with an error when the goal is invalid" do
      expect {
        post goals_path, params: { goal: { name: "", target_type: "custom", target_value: 10, status: "active" } }
      }.not_to change(Goal, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "does not link an account belonging to another user" do
      other = create(:account, user: create(:user))
      post goals_path, params: { goal: { name: "Cross", target_type: "financial", target_value: 100, status: "active", related: "Account-#{other.id}" } }
      expect(Goal.last.related).to be_nil
    end
  end

  describe "GET /goals/:id/edit" do
    it "renders the edit form" do
      goal = create(:goal, user: user)
      get edit_goal_path(goal)
      expect(response).to have_http_status(:success)
    end
  end

  describe "PATCH /goals/:id" do
    it "updates the goal attributes" do
      goal = create(:goal, user: user, name: "Old")
      patch goal_path(goal), params: { goal: { name: "New name", target_value: 250 } }
      expect(response).to redirect_to(goal_path(goal))
      goal.reload
      expect(goal.name).to eq("New name")
      expect(goal.target_value).to eq(250)
    end

    it "re-renders edit with an error when the update is invalid" do
      goal = create(:goal, user: user, name: "Keep")
      patch goal_path(goal), params: { goal: { name: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(goal.reload.name).to eq("Keep")
    end

    it "applies the related param on update" do
      account = create(:account, user: user)
      goal = create(:goal, user: user, target_type: "financial", target_value: 1000)
      patch goal_path(goal), params: { goal: { target_value: 1000, related: "Account-#{account.id}" } }
      expect(goal.reload.related).to eq(account)
    end
  end

  describe "DELETE /goals/:id" do
    it "destroys the goal" do
      goal = create(:goal, user: user)
      expect {
        delete goal_path(goal)
      }.to change(Goal, :count).by(-1)
      expect(response).to redirect_to(goals_path)
    end
  end

  describe "PATCH /goals/:id/recalculate" do
    it "recalculates progress from the linked account balance and redirects" do
      account = create(:account, user: user, initial_balance_cents: 320_00)
      goal = create(:goal, user: user, target_type: "financial", target_value: 1000, current_value: 0, status: "active", related: account)

      patch recalculate_goal_path(goal)

      expect(response).to redirect_to(goal_path(goal))
      expect(goal.reload.current_value.to_f).to eq(320.0)
    end

    it "recalculates a habit goal from completed habit logs" do
      habit = create(:habit, user: user)
      create(:habit_log, habit: habit, completed: true, date: Date.current)
      create(:habit_log, habit: habit, completed: true, date: Date.current - 1)
      goal = create(:goal, user: user, target_type: "habit", target_value: 30, current_value: 0, status: "active", related: habit)

      patch recalculate_goal_path(goal)

      expect(goal.reload.current_value.to_f).to eq(2.0)
    end
  end
end
