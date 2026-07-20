require "rails_helper"

RSpec.describe "Api::V1::Goals", type: :request do
  let(:user) { create(:user) }
  let(:auth) { { "Authorization" => "Bearer #{user.api_token}" } }

  describe "GET /api/v1/goals" do
    it "returns JSON 401 without a token" do
      get api_v1_goals_path

      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)["error"]).to eq("unauthorized")
    end

    it "groups goals by status and hides other users' goals" do
      create(:goal, user: user, name: "Active goal")
      create(:goal, user: user, name: "Done goal", status: "achieved", current_value: 100)
      create(:goal, user: user, name: "Dropped goal", status: "abandoned")
      create(:goal, name: "Someone else's")

      get api_v1_goals_path, headers: auth

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["active"].map { |g| g["name"] }).to eq([ "Active goal" ])
      expect(body["achieved"].map { |g| g["name"] }).to eq([ "Done goal" ])
      expect(body["abandoned"].map { |g| g["name"] }).to eq([ "Dropped goal" ])
    end

    it "recalculates active goals before rendering" do
      account = create(:account, user: user, initial_balance_cents: 250_00)
      create(:goal, user: user, name: "Save up", target_type: "financial", related: account,
                    target_value: 1000, current_value: 0)

      get api_v1_goals_path, headers: auth

      goal_json = JSON.parse(response.body)["active"].first
      expect(goal_json["current_value"]).to eq(250.0)
      expect(goal_json["progress_percent"]).to eq(25.0)
    end

    it "moves an active goal that reaches its target into the achieved group" do
      account = create(:account, user: user, initial_balance_cents: 500_00)
      create(:goal, user: user, name: "Small target", target_type: "financial", related: account,
                    target_value: 100, current_value: 0)

      get api_v1_goals_path, headers: auth

      body = JSON.parse(response.body)
      expect(body["active"]).to be_empty
      expect(body["achieved"].map { |g| g["name"] }).to eq([ "Small target" ])
    end

    it "serializes the full goal shape with deadline badge" do
      account = create(:account, user: user, name: "Vault", currency: "TRY", initial_balance_cents: 40_000)
      create(:goal, user: user, name: "Emergency fund", description: "3 months", target_type: "financial",
                    related: account, target_value: 1000, current_value: 0, unit: "TRY",
                    deadline: Date.current + 5, color: "#B8860B")

      get api_v1_goals_path, headers: auth

      expect(JSON.parse(response.body)["active"].first).to include(
        "name" => "Emergency fund", "description" => "3 months", "target_type" => "financial",
        "status" => "active", "color" => "#B8860B", "unit" => "TRY",
        "deadline" => (Date.current + 5).iso8601, "days_remaining" => 5,
        "target_value" => 1000.0, "current_value" => 400.0, "progress_percent" => 40.0,
        "deadline_badge" => { "state" => "soon", "days" => 5 }
      )
    end

    it "serializes a related account with balance and subunit" do
      account = create(:account, user: user, name: "Vault", currency: "TRY", initial_balance_cents: 40_000)
      create(:goal, user: user, target_type: "financial", related: account, target_value: 1000)

      get api_v1_goals_path, headers: auth

      expect(JSON.parse(response.body)["active"].first["related"]).to eq(
        "type" => "Account", "id" => account.id, "name" => "Vault",
        "balance_cents" => 40_000, "currency" => "TRY", "subunit_to_unit" => 100
      )
    end

    it "renders every deadline_badge state" do
      create(:goal, user: user, name: "Overdue", deadline: Date.current - 3)
      create(:goal, user: user, name: "Today", deadline: Date.current)
      create(:goal, user: user, name: "Soon", deadline: Date.current + 5)
      create(:goal, user: user, name: "Far", deadline: Date.current + 30)
      create(:goal, user: user, name: "No deadline")

      get api_v1_goals_path, headers: auth

      badges = JSON.parse(response.body)["active"].to_h { |g| [ g["name"], g["deadline_badge"] ] }
      expect(badges["Overdue"]).to eq("state" => "overdue", "days" => 3)
      expect(badges["Today"]).to eq("state" => "today", "days" => 0)
      expect(badges["Soon"]).to eq("state" => "soon", "days" => 5)
      expect(badges["Far"]).to eq("state" => "far", "days" => 30)
      expect(badges["No deadline"]).to be_nil
    end
  end

  describe "GET /api/v1/goals/:id" do
    it "recalculates and returns the goal" do
      habit = create(:habit, user: user, name: "Run")
      create(:habit_log, habit: habit, date: Date.current, completed: true)
      create(:habit_log, habit: habit, date: Date.current - 1, completed: true)
      goal = create(:goal, user: user, target_type: "habit", related: habit,
                           target_value: 10, current_value: 0)

      get api_v1_goal_path(goal), headers: auth

      expect(response).to have_http_status(:ok)
      goal_json = JSON.parse(response.body)["goal"]
      expect(goal_json["current_value"]).to eq(2.0)
      expect(goal_json["related"]).to include(
        "type" => "Habit", "id" => habit.id, "name" => "Run", "current_streak" => 2, "completed_days" => 2
      )
    end

    it "404s for another user's goal" do
      goal = create(:goal)

      get api_v1_goal_path(goal), headers: auth

      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)["error"]).to eq("not_found")
    end
  end

  describe "POST /api/v1/goals" do
    it "creates a goal with a composite Account related param" do
      account = create(:account, user: user, name: "Gold", currency: "GAU", initial_balance_cents: 120)

      post api_v1_goals_path, headers: auth,
           params: { name: "Gold stash", target_type: "financial", target_value: 500,
                     unit: "gr", related: "Account-#{account.id}" }, as: :json

      expect(response).to have_http_status(:created)
      goal_json = JSON.parse(response.body)["goal"]
      expect(goal_json).to include("name" => "Gold stash", "target_type" => "financial", "unit" => "gr")
      expect(goal_json["related"]).to include(
        "type" => "Account", "id" => account.id, "balance_cents" => 120, "currency" => "GAU", "subunit_to_unit" => 1
      )
    end

    it "creates a goal with a composite Habit related param" do
      habit = create(:habit, user: user, name: "Meditate")

      post api_v1_goals_path, headers: auth,
           params: { name: "Meditation streak", target_type: "habit", target_value: 30,
                     unit: "days", related: "Habit-#{habit.id}" }, as: :json

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["goal"]["related"]).to include("type" => "Habit", "id" => habit.id)
    end

    it "ignores a related param pointing at another user's account" do
      other_account = create(:account)

      post api_v1_goals_path, headers: auth,
           params: { name: "Sneaky", target_type: "financial", target_value: 100,
                     related: "Account-#{other_account.id}" }, as: :json

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["goal"]["related"]).to be_nil
    end

    it "returns 422 with field errors for an invalid goal" do
      post api_v1_goals_path, headers: auth, params: { name: "", target_value: 10 }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["errors"]).to have_key("name")
    end
  end

  describe "PATCH /api/v1/goals/:id" do
    it "updates attributes and clears related with \"none\"" do
      account = create(:account, user: user)
      goal = create(:goal, user: user, target_type: "financial", related: account)

      patch api_v1_goal_path(goal), headers: auth,
            params: { name: "Renamed", target_value: 750, related: "none" }, as: :json

      expect(response).to have_http_status(:ok)
      goal_json = JSON.parse(response.body)["goal"]
      expect(goal_json).to include("name" => "Renamed", "target_value" => 750.0)
      expect(goal_json["related"]).to be_nil
    end

    it "404s for another user's goal" do
      goal = create(:goal)

      patch api_v1_goal_path(goal), headers: auth, params: { name: "Hijack" }, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /api/v1/goals/:id/update_progress" do
    it "applies a delta" do
      goal = create(:goal, user: user, target_value: 100, current_value: 40)

      patch update_progress_api_v1_goal_path(goal), headers: auth, params: { delta: 5 }, as: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["goal"]["current_value"]).to eq(45.0)
    end

    it "sets an absolute current_value" do
      goal = create(:goal, user: user, target_value: 100, current_value: 40)

      patch update_progress_api_v1_goal_path(goal), headers: auth, params: { current_value: 90 }, as: :json

      expect(JSON.parse(response.body)["goal"]["current_value"]).to eq(90.0)
    end

    it "clamps a negative result at 0" do
      goal = create(:goal, user: user, target_value: 100, current_value: 3)

      patch update_progress_api_v1_goal_path(goal), headers: auth, params: { delta: -10 }, as: :json

      goal_json = JSON.parse(response.body)["goal"]
      expect(goal_json["current_value"]).to eq(0.0)
      expect(goal_json["status"]).to eq("active")
    end

    it "auto-achieves when the target is reached" do
      goal = create(:goal, user: user, target_value: 100, current_value: 99)

      patch update_progress_api_v1_goal_path(goal), headers: auth, params: { delta: 1 }, as: :json

      expect(JSON.parse(response.body)["goal"]["status"]).to eq("achieved")
    end

    it "keeps an abandoned goal abandoned" do
      goal = create(:goal, user: user, target_value: 100, current_value: 0, status: "abandoned")

      patch update_progress_api_v1_goal_path(goal), headers: auth, params: { current_value: 100 }, as: :json

      goal_json = JSON.parse(response.body)["goal"]
      expect(goal_json["status"]).to eq("abandoned")
      expect(goal_json["current_value"]).to eq(100.0)
    end

    it "404s for another user's goal" do
      goal = create(:goal)

      patch update_progress_api_v1_goal_path(goal), headers: auth, params: { delta: 1 }, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /api/v1/goals/:id/recalculate" do
    it "computes GAU progress with subunit_to_unit 1 (grams, not /100)" do
      account = create(:account, user: user, currency: "GAU", initial_balance_cents: 412)
      goal = create(:goal, user: user, target_type: "financial", related: account,
                           target_value: 500, current_value: 0, unit: "gr")

      patch recalculate_api_v1_goal_path(goal), headers: auth

      expect(response).to have_http_status(:ok)
      goal_json = JSON.parse(response.body)["goal"]
      expect(goal_json["current_value"]).to eq(412.0)
      expect(goal_json["progress_percent"]).to eq(82.4)
      expect(goal_json["related"]).to include("balance_cents" => 412, "subunit_to_unit" => 1)
    end

    it "computes TRY progress with subunit_to_unit 100" do
      account = create(:account, user: user, currency: "TRY", initial_balance_cents: 41_200)
      goal = create(:goal, user: user, target_type: "financial", related: account,
                           target_value: 500, current_value: 0)

      patch recalculate_api_v1_goal_path(goal), headers: auth

      goal_json = JSON.parse(response.body)["goal"]
      expect(goal_json["current_value"]).to eq(412.0)
      expect(goal_json["progress_percent"]).to eq(82.4)
    end

    it "404s for another user's goal" do
      goal = create(:goal)

      patch recalculate_api_v1_goal_path(goal), headers: auth

      expect(response).to have_http_status(:not_found)
    end
  end
end
