require "rails_helper"

RSpec.describe "Api::V1::Habits", type: :request do
  let(:user) { create(:user) }
  let(:auth) { { "Authorization" => "Bearer #{user.api_token}" } }

  it "returns JSON 401 without a token" do
    get api_v1_habits_path

    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)["error"]).to eq("unauthorized")
  end

  describe "GET /api/v1/habits" do
    context "with a completed and a pending habit" do
      let!(:run) { create(:habit, user: user, name: "Koşu", description: "Sabah", color: "#D4A853") }

      before do
        create(:habit, user: user, name: "Yoga")
        create(:habit_log, habit: run, date: Date.current, completed: true, count: 1)
        create(:habit, user: user, name: "Archived", archived_at: Time.current)
        create(:habit, name: "Someone else's")
        get api_v1_habits_path, headers: auth
      end

      it "returns only the user's active habits, ordered by name" do
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["habits"].map { |h| h["name"] }).to eq([ "Koşu", "Yoga" ])
      end

      it "serializes habit fields with today's log" do
        kosu = JSON.parse(response.body)["habits"].first
        expect(kosu).to include(
          "id" => run.id, "description" => "Sabah", "frequency" => "daily", "target_count" => 1,
          "color" => "#D4A853", "goal_id" => nil, "current_streak" => 1, "longest_streak" => 1,
          "completion_rate_30d" => 3.3
        )
        expect(kosu["today"]).to eq("date" => Date.current.iso8601, "completed" => true, "count" => 1)
        expect(kosu["period"]).to be_nil
      end

      it "builds an untrimmed 14-day chain ending today" do
        chain = JSON.parse(response.body)["habits"].first["chain"]
        expect(chain.length).to eq(14)
        expect(chain.first).to eq("date" => (Date.current - 13).iso8601, "status" => "missed")
        expect(chain.last).to eq("date" => Date.current.iso8601, "status" => "completed")
      end

      it "marks unlogged habits as today_pending" do
        yoga = JSON.parse(response.body)["habits"].last
        expect(yoga["today"]).to eq("date" => Date.current.iso8601, "completed" => false, "count" => 0)
        expect(yoga["chain"].last["status"]).to eq("today_pending")
      end

      it "returns meta with completed_today and the perfect day chain" do
        meta = JSON.parse(response.body)["meta"]
        expect(meta).to include("completed_today" => 1, "total_active" => 2)
        expect(meta["perfect_day"]["chain"].last).to eq("date" => Date.current.iso8601, "status" => "partial")
        expect(meta["perfect_day"]).to include("current_streak" => 0, "longest_streak" => 0)
      end
    end

    it "computes the streak from seeded logs" do
      habit = create(:habit, user: user)
      [ 0, 1, 2, 4 ].each { |n| create(:habit_log, habit: habit, date: Date.current - n) }

      get api_v1_habits_path, headers: auth

      body = JSON.parse(response.body)
      expect(body["habits"].first).to include("current_streak" => 3, "longest_streak" => 3)
    end

    it "includes the period block for weekly habits" do
      habit = create(:habit, user: user, frequency: "weekly", target_count: 3)
      create(:habit_log, habit: habit, date: Date.current.beginning_of_week)

      get api_v1_habits_path, headers: auth

      period = JSON.parse(response.body)["habits"].first["period"]
      expect(period).to eq(
        "range_start" => Date.current.beginning_of_week.iso8601,
        "range_end" => Date.current.end_of_week.iso8601,
        "completed_count" => 1,
        "complete" => false
      )
    end
  end

  describe "GET /api/v1/habits/:id" do
    it "returns an untrimmed chain sized by ?days" do
      habit = create(:habit, user: user)
      create(:habit_log, habit: habit, date: Date.current - 1)

      get api_v1_habit_path(habit, days: 84), headers: auth

      chain = JSON.parse(response.body)["habit"]["chain"]
      expect(chain.length).to eq(84)
      expect(chain.first).to eq("date" => (Date.current - 83).iso8601, "status" => "missed")
      expect(chain.last["status"]).to eq("today_pending")
    end

    it "defaults the chain to 30 days" do
      habit = create(:habit, user: user)

      get api_v1_habit_path(habit), headers: auth

      expect(JSON.parse(response.body)["habit"]["chain"].length).to eq(30)
    end

    it "404s for another user's habit" do
      other = create(:habit)

      get api_v1_habit_path(other), headers: auth

      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)["error"]).to eq("not_found")
    end
  end

  describe "PATCH /api/v1/habits/:id/toggle_today" do
    it "flips a target_count=1 habit on" do
      habit = create(:habit, user: user, target_count: 1)

      patch toggle_today_api_v1_habit_path(habit), headers: auth

      body = JSON.parse(response.body)
      expect(body["habit"]["today"]).to include("completed" => true, "count" => 1)
      expect(body["habit"]["current_streak"]).to eq(1)
      expect(body["meta"]).to include("completed_today" => 1, "total_active" => 1)
      expect(body["meta"]["perfect_day"]["current_streak"]).to eq(1)
    end

    it "flips a completed habit back off" do
      habit = create(:habit, user: user, target_count: 1)
      create(:habit_log, habit: habit, date: Date.current, completed: true, count: 1)

      patch toggle_today_api_v1_habit_path(habit), headers: auth

      body = JSON.parse(response.body)
      expect(body["habit"]["today"]).to include("completed" => false, "count" => 0)
      expect(body["meta"]["completed_today"]).to eq(0)
    end

    it "applies deltas with a clamp for target_count>1 habits" do
      habit = create(:habit, user: user, target_count: 3)

      patch toggle_today_api_v1_habit_path(habit), params: { delta: 2 }, headers: auth

      body = JSON.parse(response.body)
      expect(body["habit"]["today"]).to include("completed" => false, "count" => 2)
      expect(body["habit"]["chain"].last).to eq(
        "date" => Date.current.iso8601, "status" => "partial", "completed" => 2, "possible" => 3
      )

      patch toggle_today_api_v1_habit_path(habit), params: { delta: 2 }, headers: auth

      body = JSON.parse(response.body)
      expect(body["habit"]["today"]).to include("completed" => true, "count" => 3)

      patch toggle_today_api_v1_habit_path(habit), params: { delta: -1 }, headers: auth

      expect(JSON.parse(response.body)["habit"]["today"]).to include("completed" => false, "count" => 2)
    end

    it "404s for another user's habit" do
      other = create(:habit)

      patch toggle_today_api_v1_habit_path(other), headers: auth

      expect(response).to have_http_status(:not_found)
      expect(other.habit_logs.count).to eq(0)
    end
  end

  describe "POST /api/v1/habits" do
    it "creates a habit linked to one of the user's goals" do
      goal = create(:goal, user: user)

      post api_v1_habits_path,
        params: { name: "Koşu", frequency: "weekly", target_count: 3, color: "#D4A853", goal_id: goal.id },
        headers: auth

      expect(response).to have_http_status(:created)
      habit = JSON.parse(response.body)["habit"]
      expect(habit).to include(
        "name" => "Koşu", "frequency" => "weekly", "target_count" => 3, "color" => "#D4A853", "goal_id" => goal.id
      )
      expect(habit["period"]).to include("completed_count" => 0, "complete" => false)
    end

    it "404s for another user's goal_id" do
      goal = create(:goal)

      post api_v1_habits_path, params: { name: "Koşu", goal_id: goal.id }, headers: auth

      expect(response).to have_http_status(:not_found)
      expect(user.habits.count).to eq(0)
    end

    it "422s with field errors for an invalid habit" do
      post api_v1_habits_path, params: { name: "", frequency: "hourly" }, headers: auth

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["errors"].keys).to include("name", "frequency")
    end
  end

  describe "PATCH /api/v1/habits/:id" do
    it "updates a habit" do
      habit = create(:habit, user: user, name: "Eski")

      patch api_v1_habit_path(habit), params: { name: "Yeni", target_count: 2 }, headers: auth

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["habit"]).to include("name" => "Yeni", "target_count" => 2)
    end

    it "422s for invalid attributes" do
      habit = create(:habit, user: user)

      patch api_v1_habit_path(habit), params: { target_count: 0 }, headers: auth

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["errors"]).to have_key("target_count")
    end

    it "404s for another user's habit" do
      other = create(:habit, name: "Theirs")

      patch api_v1_habit_path(other), params: { name: "Mine now" }, headers: auth

      expect(response).to have_http_status(:not_found)
      expect(other.reload.name).to eq("Theirs")
    end
  end

  describe "PATCH /api/v1/habits/:id/archive" do
    it "archives the habit and hides it from the index" do
      habit = create(:habit, user: user)

      patch archive_api_v1_habit_path(habit), headers: auth

      expect(response).to have_http_status(:ok)
      expect(habit.reload.archived_at).to be_present

      get api_v1_habits_path, headers: auth

      body = JSON.parse(response.body)
      expect(body["habits"]).to be_empty
      expect(body["meta"]["total_active"]).to eq(0)
    end

    it "404s for another user's habit" do
      other = create(:habit)

      patch archive_api_v1_habit_path(other), headers: auth

      expect(response).to have_http_status(:not_found)
      expect(other.reload.archived_at).to be_nil
    end
  end
end
