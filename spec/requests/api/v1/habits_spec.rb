require "rails_helper"

RSpec.describe "Api::V1::Habits", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:auth) { { "Authorization" => "Bearer #{user.api_token}" } }

  it "returns JSON 401 without a token" do
    get api_v1_habits_path

    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)["error"]).to eq("unauthorized")
  end

  describe "GET /api/v1/habits" do
    context "with a completed and a pending habit" do
      let!(:run) { create(:habit, user: user, name: "Koşu", description: "Sabah", color: "#D4A853", created_at: 40.days.ago) }

      before do
        create(:habit, user: user, name: "Yoga", created_at: 40.days.ago)
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

    # Days before the habit existed were not missed: a habit made and done
    # today used to read 1 of 30 days (3.3%) with 13 "missed" chain days.
    context "with a habit created today" do
      let!(:habit) { create(:habit, user: user, created_at: Time.current) }

      before { create(:habit_log, habit: habit, date: Date.current, completed: true, count: 1) }

      it "rates and chains only the days since its start date" do
        get api_v1_habits_path, headers: auth

        json = JSON.parse(response.body)["habits"].sole
        expect(json).to include("start_date" => Date.current.iso8601, "completion_rate_30d" => 100.0)
        expect(json["chain"]).to eq([ { "date" => Date.current.iso8601, "status" => "completed" } ])
      end

      it "starts the detail chain and the logged chain at the start date too" do
        get api_v1_habit_path(habit, days: 84), headers: auth
        expect(JSON.parse(response.body)["habit"]["chain"].map { |c| c["date"] }).to eq([ Date.current.iso8601 ])

        put log_api_v1_habit_path(habit, date: Date.current.iso8601, days: 30), params: { count: 0 }, headers: auth, as: :json
        body = JSON.parse(response.body)["habit"]
        expect(body["chain"]).to eq([ { "date" => Date.current.iso8601, "status" => "today_pending" } ])
        expect(body["completion_rate_30d"]).to eq(0.0)
      end
    end

    it "rates a habit started inside the window over the days since then" do
      habit = create(:habit, user: user, created_at: 3.days.ago)
      [ 0, 2 ].each { |n| create(:habit_log, habit: habit, date: Date.current - n) }

      get api_v1_habits_path, headers: auth

      json = JSON.parse(response.body)["habits"].sole
      expect(json["completion_rate_30d"]).to eq(50.0)
      expect(json["chain"].map { |c| c["status"] }).to eq(%w[missed completed missed completed])
    end

    it "keeps logged days from before the start date in the chain and the rate" do
      habit = create(:habit, user: user, created_at: Time.current)
      create(:habit_log, habit: habit, date: Date.current - 4)

      get api_v1_habits_path, headers: auth

      json = JSON.parse(response.body)["habits"].sole
      expect(json["chain"].first).to eq("date" => (Date.current - 4).iso8601, "status" => "completed")
      expect(json["chain"].length).to eq(5)
      expect(json["completion_rate_30d"]).to eq(20.0)
    end
  end

  describe "GET /api/v1/habits/:id" do
    it "uses the default chain length for a days value that is a list or an object" do
      habit = create(:habit, user: user, created_at: 100.days.ago)

      get "#{api_v1_habit_path(habit)}?days[]=1", headers: auth
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["habit"]["chain"].length).to eq(30)

      get "#{api_v1_habit_path(habit)}?days[a]=1", headers: auth
      expect(response).to have_http_status(:ok)
    end

    it "returns an untrimmed chain sized by ?days" do
      habit = create(:habit, user: user, created_at: 100.days.ago)
      create(:habit_log, habit: habit, date: Date.current - 1)

      get api_v1_habit_path(habit, days: 84), headers: auth

      chain = JSON.parse(response.body)["habit"]["chain"]
      expect(chain.length).to eq(84)
      expect(chain.first).to eq("date" => (Date.current - 83).iso8601, "status" => "missed")
      expect(chain.last["status"]).to eq("today_pending")
    end

    it "defaults the chain to 30 days" do
      habit = create(:habit, user: user, created_at: 100.days.ago)

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

  describe "PUT /api/v1/habits/:id/logs/:date" do
    let(:habit) { create(:habit, user: user, name: "Su", target_count: 3, created_at: 40.days.ago) }

    def put_log(date, params, target: habit)
      put log_api_v1_habit_path(target, date: date.to_s), params: params, headers: auth, as: :json
      JSON.parse(response.body)
    end

    it "401s without a token" do
      put log_api_v1_habit_path(habit, date: Date.current.iso8601), params: { count: 1 }

      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)["code"]).to eq("unauthorized")
    end

    it "sets today's count and returns the log and the meta" do
      body = put_log(Date.current, { count: 2 })

      expect(response).to have_http_status(:ok)
      expect(body["log"]).to eq("date" => Date.current.iso8601, "count" => 2, "completed" => false)
      expect(body["meta"]).to include("completed_today" => 0, "total_active" => 1)
    end

    it "returns the habit exactly as GET /habits lists it" do
      body = put_log(Date.current, { count: 2 })

      get api_v1_habits_path, headers: auth
      expect(body["habit"]).to eq(JSON.parse(response.body)["habits"].sole)
      expect(body["habit"]["today"]).to eq("date" => Date.current.iso8601, "completed" => false, "count" => 2)
      expect(body["habit"]["chain"].length).to eq(14)
    end

    it "is idempotent: repeating the request leaves the same state" do
      2.times { put_log(Date.current, { count: 3 }) }

      expect(habit.habit_logs.pluck(:date, :count, :completed)).to eq([ [ Date.current, 3, true ] ])
      expect(JSON.parse(response.body)["meta"]["completed_today"]).to eq(1)
    end

    it "backfills a past day and reflects it in the chain and streak" do
      create(:habit_log, habit: habit, date: Date.current - 1, count: 3, completed: true)

      body = put_log(Date.current - 2, { completed: true })

      expect(body["log"]).to eq("date" => (Date.current - 2).iso8601, "count" => 3, "completed" => true)
      expect(body["habit"]["chain"].last(3).map { |day| day["status"] }).to eq(%w[completed completed today_pending])
      expect(body["habit"]["current_streak"]).to eq(2)
    end

    it "removes the log for count 0 or completed false" do
      create(:habit_log, habit: habit, date: Date.current - 1, count: 3, completed: true)
      create(:habit_log, habit: habit, date: Date.current, count: 1, completed: false)

      put_log(Date.current - 1, { count: 0 })
      body = put_log(Date.current, { completed: false })

      expect(habit.habit_logs).to be_empty
      expect(body["log"]).to eq("date" => Date.current.iso8601, "count" => 0, "completed" => false)
    end

    it "clamps a count above the target and lets count win over completed" do
      body = put_log(Date.current, { count: 9, completed: false })

      expect(body["log"]).to include("count" => 3, "completed" => true)
    end

    it "accepts form-encoded params" do
      put log_api_v1_habit_path(habit, date: Date.current.iso8601), params: { count: "1" }, headers: auth

      expect(response).to have_http_status(:ok)
      expect(habit.habit_logs.sole.count).to eq(1)
    end

    it "treats any positive count as a done day for weekly habits" do
      weekly = create(:habit, user: user, frequency: "weekly", target_count: 3)

      body = put_log(Date.current, { count: 1 }, target: weekly)

      expect(body["log"]).to include("count" => 3, "completed" => true)
      expect(body["habit"]["period"]).to include("completed_count" => 1, "complete" => false)
    end

    it "honours ?days for the returned chain" do
      put log_api_v1_habit_path(habit, date: Date.current.iso8601, days: 30), params: { count: 1 }, headers: auth, as: :json

      expect(JSON.parse(response.body)["habit"]["chain"].length).to eq(30)
    end

    it "422s with code future_date for a day after today" do
      body = put_log(Date.current + 1, { count: 1 })

      expect(response).to have_http_status(:unprocessable_content)
      expect(body).to include("code" => "future_date")
      expect(body["errors"]).to have_key("date")
      expect(habit.habit_logs).to be_empty
    end

    it "422s with code before_habit_start for a day before the habit existed" do
      body = put_log(Date.current - 41, { count: 1 })

      expect(response).to have_http_status(:unprocessable_content)
      expect(body).to include("code" => "before_habit_start", "habit_start" => habit.created_at.to_date.iso8601)
      expect(habit.habit_logs).to be_empty
    end

    it "422s with code habit_archived for an archived habit" do
      habit.update!(archived_at: Time.current)

      body = put_log(Date.current, { count: 1 })

      expect(response).to have_http_status(:unprocessable_content)
      expect(body["code"]).to eq("habit_archived")
      expect(habit.habit_logs).to be_empty
    end

    it "422s with code invalid_date for a malformed date" do
      [ "2026-13-45", "yesterday", "04.10.2026" ].each do |date|
        expect(put_log(date, { count: 1 })).to include("code" => "invalid_date", "param" => "date")
      end
      expect(response).to have_http_status(:unprocessable_content)
    end

    # Date.iso8601 alone reads these as a day ("2026-10" is 1 October).
    it "422s with code invalid_date for ISO 8601 forms other than YYYY-MM-DD, writing nothing" do
      travel_to Time.zone.local(2026, 10, 5, 12) do
        old_habit = create(:habit, user: user, created_at: 1.month.ago)

        [ "2026-10", "20261004", "2026-W40-7", "2026-277", "2026-10-04T23:30:00-05:00" ].each do |date|
          body = put_log(date, { count: 1 }, target: old_habit)
          expect(body).to include("code" => "invalid_date"), "for #{date.inspect}"
          expect(response).to have_http_status(:unprocessable_content)
        end
        expect(old_habit.habit_logs).to be_empty
      end
    end

    it "422s with code invalid_parameter for a days value that is not an integer, writing nothing" do
      [ [ 30 ], "abc", 1.5 ].each do |days|
        body = put_log(Date.current, { count: 1, days: days })
        expect(response).to have_http_status(:unprocessable_content)
        expect(body).to include("code" => "invalid_parameter", "param" => "days"), "for #{days.inspect}"
      end
      expect(habit.habit_logs).to be_empty
    end

    it "falls back to a 14-day chain for a days value outside 1..366" do
      [ 0, 367 ].each do |days|
        body = put_log(Date.current, { count: 1, days: days })
        expect(response).to have_http_status(:ok)
        expect(body["habit"]["chain"].length).to eq(14)
      end
    end

    it "422s with code invalid_parameter for a bad or missing count" do
      [ { count: -1 }, { count: 1.5 }, { count: "two" }, { completed: "maybe" }, {} ].each do |params|
        body = put_log(Date.current, params)
        expect(body).to include("code" => "invalid_parameter"), "for #{params.inspect}"
      end
      expect(habit.habit_logs).to be_empty
    end

    it "404s for another user's habit without touching it" do
      other = create(:habit)

      body = put_log(Date.current, { count: 1 }, target: other)

      expect(response).to have_http_status(:not_found)
      expect(body).to eq("error" => "not_found", "code" => "not_found")
      expect(other.habit_logs).to be_empty
    end
  end

  # G4: archived list, unarchive, delete, every editable field.
  describe "G4 changes" do
    def body = JSON.parse(response.body)

  # The SQL statements matching +pattern+ that the block runs.
  def sql_during(pattern)
    statements = []
    counter = ->(*, payload) { statements << payload[:sql] if payload[:sql].match?(pattern) }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    statements
  end

    def patch_habit(habit, params)
      patch api_v1_habit_path(habit), params: params, headers: auth, as: :json
      body
    end

    it "401s on the new endpoints without a token" do
      habit = create(:habit, user: user, archived_at: 1.day.ago)

      get api_v1_habits_path(archived: true)
      expect(response).to have_http_status(:unauthorized)
      patch unarchive_api_v1_habit_path(habit)
      expect(response).to have_http_status(:unauthorized)
      delete api_v1_habit_path(habit)
      expect(response).to have_http_status(:unauthorized)
      expect(body["code"]).to eq("unauthorized")
      expect(habit.reload.archived_at).to be_present
    end

    describe "the habit object" do
      it "carries archived, archived_at, created_at and start_date" do
        travel_to Time.zone.local(2026, 10, 4, 12) do
          create(:habit, user: user, created_at: Time.zone.local(2026, 9, 20, 8))

          get api_v1_habits_path, headers: auth

          expect(body["habits"].sole).to include(
            "archived" => false, "archived_at" => nil,
            "created_at" => "2026-09-20T08:00:00.000Z", "start_date" => "2026-09-20"
          )
        end
      end

      it "gives start_date in the user's zone, the first day PUT logs/:date accepts" do
        user.update!(timezone: "Istanbul")
        travel_to Time.utc(2026, 10, 4, 12) do
          habit = create(:habit, user: user, created_at: Time.utc(2026, 9, 19, 22, 30))

          get api_v1_habit_path(habit), headers: auth
          expect(body["habit"]["start_date"]).to eq("2026-09-20")

          put log_api_v1_habit_path(habit, date: "2026-09-20"), params: { count: 1 }, headers: auth, as: :json
          expect(response).to have_http_status(:ok)
          put log_api_v1_habit_path(habit, date: "2026-09-19"), params: { count: 1 }, headers: auth, as: :json
          expect(body).to include("code" => "before_habit_start", "habit_start" => "2026-09-20")
        end
      end
    end

    describe "GET /api/v1/habits?archived=true" do
      it "lists only the user's archived habits, most recently archived first, with the active meta" do
        create(:habit, user: user, name: "Aktif")
        create(:habit, user: user, name: "Eski", archived_at: 5.days.ago)
        create(:habit, user: user, name: "Yeni", archived_at: 1.day.ago)
        create(:habit, name: "Başkasının", archived_at: 1.day.ago)

        get api_v1_habits_path(archived: true), headers: auth

        expect(response).to have_http_status(:ok)
        expect(body["habits"].map { |h| [ h["name"], h["archived"] ] }).to eq([ [ "Yeni", true ], [ "Eski", true ] ])
        expect(body["meta"]).to include("total_active" => 1, "completed_today" => 0)
      end

      it "ends each archived habit's chain on the day it was archived" do
        travel_to Time.zone.local(2026, 10, 4, 12) do
          habit = create(:habit, user: user, created_at: 30.days.ago, archived_at: Time.zone.local(2026, 9, 25, 18))
          create(:habit_log, habit: habit, date: Date.new(2026, 9, 25))

          get api_v1_habits_path(archived: true), headers: auth

          chain = body["habits"].sole["chain"]
          expect(chain.length).to eq(14)
          expect(chain.first["date"]).to eq("2026-09-12")
          expect(chain.last).to eq("date" => "2026-09-25", "status" => "completed")
        end
      end

      it "reads every archived habit's chain in one log query, and keeps a streak only for one archived since yesterday" do
        travel_to Time.zone.local(2026, 10, 4, 12) do
          { "Eski" => Date.new(2026, 9, 1), "Yeni" => Date.new(2026, 10, 3) }.each do |name, last_day|
            habit = create(:habit, user: user, name: name, created_at: 60.days.ago, archived_at: last_day.in_time_zone.change(hour: 20))
            [ last_day - 1, last_day ].each { |date| create(:habit_log, habit: habit, date: date) }
          end
          chain_queries = sql_during(/SELECT "habit_logs"\.\* FROM "habit_logs" WHERE .*"date" BETWEEN/) do
            get api_v1_habits_path(archived: true), headers: auth
          end

          habits = body["habits"].index_by { |h| h["name"] }
          expect(habits.transform_values { |h| h["current_streak"] }).to eq("Yeni" => 2, "Eski" => 0)
          expect(habits["Eski"]["chain"].last).to eq("date" => "2026-09-01", "status" => "completed")
          expect(chain_queries.size).to eq(1)
        end
      end

      it "lists the active habits for archived=false" do
        create(:habit, user: user, name: "Aktif")
        create(:habit, user: user, name: "Arşiv", archived_at: 1.day.ago)

        get api_v1_habits_path(archived: false), headers: auth

        expect(body["habits"].map { |h| h["name"] }).to eq([ "Aktif" ])
      end

      it "422s with invalid_parameter for an archived value that is not a boolean" do
        get api_v1_habits_path(archived: "maybe"), headers: auth

        expect(response).to have_http_status(:unprocessable_content)
        expect(body).to include("code" => "invalid_parameter", "param" => "archived")
      end
    end

    describe "GET /api/v1/habits/:id" do
      it "adds the logged and completed day counts and the goals that count the habit" do
        habit = create(:habit, user: user, target_count: 3, created_at: 10.days.ago)
        create(:habit_log, habit: habit, date: Date.current, count: 3, completed: true)
        create(:habit_log, habit: habit, date: Date.current - 1, count: 1, completed: false)
        create(:habit_log, habit: habit, date: Date.current - 2, count: 0, completed: false)
        goal = create(:goal, user: user, name: "30 gün", target_type: "habit", related: habit)

        get api_v1_habit_path(habit), headers: auth

        expect(body["habit"]).to include(
          "logged_days_count" => 2, "completed_days_count" => 1,
          "tracked_by_goals" => [ { "id" => goal.id, "name" => "30 gün", "status" => "active" } ]
        )
      end

      it "opens an archived habit with its chain ending on the archive day" do
        habit = create(:habit, user: user, created_at: 40.days.ago, archived_at: 3.days.ago)

        get api_v1_habit_path(habit, days: 7), headers: auth

        expect(body["habit"]).to include("archived" => true)
        expect(body["habit"]["chain"].last["date"]).to eq((Date.current - 3).iso8601)
      end
    end

    describe "PATCH /api/v1/habits/:id/archive" do
      it "keeps the first archived_at when archiving again" do
        archived_at = Time.zone.local(2026, 9, 1, 10)
        habit = create(:habit, user: user, archived_at: archived_at)

        patch archive_api_v1_habit_path(habit), headers: auth

        expect(response).to have_http_status(:ok)
        expect(habit.reload.archived_at).to eq(archived_at)
        expect(body["habit"]).to include("archived" => true)
      end
    end

    describe "PATCH /api/v1/habits/:id/unarchive" do
      it "unarchives the habit and returns it with its chain ending today" do
        habit = create(:habit, user: user, archived_at: 2.days.ago, created_at: 10.days.ago)

        patch unarchive_api_v1_habit_path(habit), headers: auth

        expect(response).to have_http_status(:ok)
        expect(body["habit"]).to include("id" => habit.id, "archived" => false, "archived_at" => nil)
        expect(body["habit"]["chain"].last["date"]).to eq(Date.current.iso8601)
        expect(habit.reload.archived_at).to be_nil
      end

      it "brings the habit back to the active list, loggable again" do
        habit = create(:habit, user: user, name: "Dönüş", archived_at: 2.days.ago, created_at: 10.days.ago)

        patch unarchive_api_v1_habit_path(habit), headers: auth
        get api_v1_habits_path, headers: auth
        expect(body["habits"].map { |h| h["name"] }).to eq([ "Dönüş" ])

        put log_api_v1_habit_path(habit, date: Date.current.iso8601), params: { count: 1 }, headers: auth, as: :json
        expect(response).to have_http_status(:ok)
      end

      it "is idempotent on an active habit" do
        habit = create(:habit, user: user)

        patch unarchive_api_v1_habit_path(habit), headers: auth

        expect(response).to have_http_status(:ok)
        expect(habit.reload.archived_at).to be_nil
      end

      it "404s for another user's habit and leaves it archived" do
        other = create(:habit, archived_at: 1.day.ago)

        patch unarchive_api_v1_habit_path(other), headers: auth

        expect(response).to have_http_status(:not_found)
        expect(body).to eq("error" => "not_found", "code" => "not_found")
        expect(other.reload.archived_at).to be_present
      end
    end

    describe "DELETE /api/v1/habits/:id" do
      it "deletes the habit and its logs, leaving other habits alone" do
        habit = create(:habit, user: user)
        other_habit = create(:habit, user: user)
        create(:habit_log, habit: habit)
        create(:habit_log, habit: other_habit)

        delete api_v1_habit_path(habit), headers: auth

        expect(response).to have_http_status(:no_content)
        expect(response.body).to be_empty
        expect(Habit.exists?(habit.id)).to be(false)
        expect(HabitLog.where(habit_id: habit.id)).to be_empty
        expect(other_habit.habit_logs.count).to eq(1)
      end

      it "unlinks the goals that counted it, which keep its final count and are logged by hand from then on" do
        habit = create(:habit, user: user)
        tracking = create(:goal, user: user, target_type: "habit", related: habit, target_value: 10, current_value: 0)
        4.times { |n| create(:habit_log, habit: habit, date: Date.current - n) }
        served = create(:goal, user: user)
        habit.update!(goal: served)

        delete api_v1_habit_path(habit), headers: auth

        expect(tracking.reload).to have_attributes(related_type: nil, related_id: nil, current_value: 4)
        expect(Goal.exists?(served.id)).to be(true)

        get api_v1_goal_path(tracking), headers: auth
        expect(body["goal"]).to include("related" => nil, "progress_source" => "manual", "current_value" => 4.0)
      end

      it "deletes an archived habit too" do
        habit = create(:habit, user: user, archived_at: 1.day.ago)

        delete api_v1_habit_path(habit), headers: auth

        expect(response).to have_http_status(:no_content)
        expect(Habit.exists?(habit.id)).to be(false)
      end

      it "404s for another user's habit and deletes nothing" do
        other = create(:habit)
        create(:habit_log, habit: other)

        delete api_v1_habit_path(other), headers: auth

        expect(response).to have_http_status(:not_found)
        expect(body).to eq("error" => "not_found", "code" => "not_found")
        expect(other.reload.habit_logs.count).to eq(1)
      end
    end

    describe "PATCH /api/v1/habits/:id (every field)" do
      it "updates every field the web form edits, plus the goal, in one request" do
        goal = create(:goal, user: user)
        habit = create(:habit, user: user)

        json = patch_habit(habit, {
          name: "Kitap", description: "Her gün 20 sayfa", frequency: "weekly",
          target_count: 4, color: "#6B8E5A", goal_id: goal.id
        })

        expect(response).to have_http_status(:ok)
        expect(json["habit"]).to include(
          "name" => "Kitap", "description" => "Her gün 20 sayfa", "frequency" => "weekly",
          "target_count" => 4, "color" => "#6B8E5A", "goal_id" => goal.id
        )
        expect(json["habit"]["period"]).to include("completed_count" => 0, "complete" => false)
      end

      it "changes only the keys sent" do
        habit = create(:habit, user: user, name: "Eski", description: "Kalsın", color: "#123456")

        patch_habit(habit, { name: "Yeni" })

        expect(habit.reload).to have_attributes(name: "Yeni", description: "Kalsın", color: "#123456")
      end

      it "unlinks the goal with goal_id null" do
        habit = create(:habit, user: user, goal: create(:goal, user: user))

        expect(patch_habit(habit, { goal_id: nil })["habit"]["goal_id"]).to be_nil
        expect(habit.reload.goal_id).to be_nil
      end

      it "404s for another user's goal and changes nothing" do
        habit = create(:habit, user: user, name: "Aynı")

        json = patch_habit(habit, { name: "Değişti", goal_id: create(:goal).id })

        expect(response).to have_http_status(:not_found)
        expect(json["code"]).to eq("not_found")
        expect(habit.reload).to have_attributes(name: "Aynı", goal_id: nil)
      end

      it "422s with invalid_parameter for a goal_id or target_count that is not a whole number" do
        habit = create(:habit, user: user, target_count: 2)

        [ { goal_id: "abc" }, { target_count: "abc" }, { target_count: 1.5 }, { target_count: "" } ].each do |params|
          json = patch_habit(habit, params)
          expect(json).to include("code" => "invalid_parameter", "param" => params.keys.first.to_s), "for #{params.inspect}"
        end
        expect(habit.reload.target_count).to eq(2)
      end

      it "accepts target_count as a string of digits" do
        habit = create(:habit, user: user)

        expect(patch_habit(habit, { target_count: "3" })["habit"]["target_count"]).to eq(3)
      end

      it "422s with validation_failed for a target below 1, a null target or an unknown frequency" do
        habit = create(:habit, user: user)

        json = patch_habit(habit, { target_count: 0, frequency: "hourly" })
        expect(json["code"]).to eq("validation_failed")
        expect(json["details"]).to include(
          "target_count" => [ { "error" => "greater_than", "value" => 0, "count" => 0 } ],
          "frequency" => [ { "error" => "inclusion", "value" => "hourly" } ]
        )

        expect(patch_habit(habit, { target_count: nil })["details"]["target_count"]).to eq([ { "error" => "not_a_number", "value" => nil } ])
      end

      it "422s with value_out_of_range for a target_count past the 4-byte column" do
        habit = create(:habit, user: user)

        expect(patch_habit(habit, { target_count: 3_000_000_000 })["code"]).to eq("value_out_of_range")
      end

      it "422s with validation_failed for a color that is not #RRGGBB, but keeps an old color editable" do
        habit = create(:habit, user: user)
        habit.update_columns(color: "gold")

        json = patch_habit(habit, { color: "red" })
        expect(json["details"]["color"]).to eq([ { "error" => "invalid" } ])

        expect(patch_habit(habit, { name: "Renk aynı" })["habit"]).to include("name" => "Renk aynı", "color" => "gold")
      end

      it "edits an archived habit" do
        habit = create(:habit, user: user, archived_at: 1.day.ago)

        expect(patch_habit(habit, { name: "Arşivde" })["habit"]).to include("name" => "Arşivde", "archived" => true)
      end
    end

    describe "POST /api/v1/habits" do
      it "422s with validation_failed for a bad color and with invalid_parameter for a bad target" do
        post api_v1_habits_path, params: { name: "Renkli", color: "blue" }, headers: auth, as: :json
        expect(body["details"]["color"]).to eq([ { "error" => "invalid" } ])

        post api_v1_habits_path, params: { name: "Sayılı", target_count: "iki" }, headers: auth, as: :json
        expect(body).to include("code" => "invalid_parameter", "param" => "target_count")
        expect(user.habits).to be_empty
      end
    end

    describe "PATCH /api/v1/habits/:id/toggle_today" do
      it "ignores a delta of any shape on a target_count 1 habit and flips the day" do
        habit = create(:habit, user: user, target_count: 1)

        [ [ 1 ], { a: 1 }, true ].each do |delta|
          patch toggle_today_api_v1_habit_path(habit), params: { delta: delta }, headers: auth, as: :json
          expect(response).to have_http_status(:ok), "for #{delta.inspect}"
        end
        expect(habit.habit_logs.find_by(date: Date.current).completed).to be(true)
      end

      it "reads a list delta on a counter habit as no delta (a flip), not a 500" do
        habit = create(:habit, user: user, target_count: 3)

        patch toggle_today_api_v1_habit_path(habit), params: { delta: [ 1 ] }, headers: auth, as: :json

        expect(response).to have_http_status(:ok)
        expect(habit.habit_logs.find_by(date: Date.current)).to have_attributes(count: 3, completed: true)
      end

      it "422s with habit_archived for an archived habit, as PUT logs/:date does" do
        habit = create(:habit, user: user, archived_at: 1.day.ago)

        patch toggle_today_api_v1_habit_path(habit), headers: auth

        expect(response).to have_http_status(:unprocessable_content)
        expect(body["code"]).to eq("habit_archived")
        expect(habit.habit_logs).to be_empty
      end
    end
  end
end
