require "rails_helper"

RSpec.describe "Api::V1::Home", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:auth) { { "Authorization" => "Bearer #{user.api_token}" } }
  let(:today) { Date.current }

  before { travel_to Time.zone.local(2026, 6, 17, 12) }
  after  { travel_back }

  it "returns JSON 401 without a token" do
    get api_v1_home_path

    expect(response).to have_http_status(:unauthorized)
    expect(response.media_type).to eq("application/json")
    expect(JSON.parse(response.body)["error"]).to eq("unauthorized")
  end

  describe "dashboard aggregates" do
    let(:body) { JSON.parse(response.body) }

    before do
      account = create(:account, user: user)
      create(:transaction, :income, user: user, account: account, amount_cents: 500_00, date: today)
      create(:transaction, user: user, account: account, amount_cents: 120_00, date: today)
      create(:transaction, user: user, account: account, amount_cents: 80_00, date: today - 2.days)
      create(:transaction, user: user, account: account, amount_cents: 999_00, date: today.prev_month)

      run_habit = create(:habit, user: user, name: "A koşu", created_at: 10.days.ago)
      read_habit = create(:habit, user: user, name: "B kitap", target_count: 3)
      create(:habit, user: user, name: "Archived", archived_at: 1.day.ago)
      create(:habit_log, habit: run_habit, date: today, completed: true, count: 1)
      create(:habit_log, habit: run_habit, date: today - 1.day, completed: true, count: 1)
      create(:habit_log, habit: read_habit, date: today, completed: false, count: 1)

      list = create(:todo_list, user: user, name: "Ev")
      create(:todo, user: user, title: "Geciken", due_at: 2.days.ago, todo_list: list)
      create(:todo, user: user, title: "Yakında", due_at: 3.days.from_now, priority: "high")
      create(:todo, user: user, title: "Uzak", due_at: 10.days.from_now)
      create(:todo, user: user, title: "Bitti", status: "done", due_at: 1.day.from_now)

      create(:event, user: user, title: "Toplantı",
             start_at: Time.current.change(hour: 9), end_at: Time.current.change(hour: 10))
      create(:event, user: user, title: "Yarın", start_at: 1.day.from_now)
      create(:event, user: user, title: "Dün", start_at: 1.day.ago)

      create(:goal, user: user, name: "Hedef 1", position: 1, target_value: 100, current_value: 25, color: "#123456")
      create(:goal, user: user, name: "Hedef 2", position: 2)
      create(:goal, user: user, name: "Hedef 3", position: 3)
      create(:goal, user: user, name: "Hedef 4", position: 4)
      create(:goal, user: user, name: "Bitmiş", status: "achieved", position: 0)

      get api_v1_home_path, headers: auth
    end

    it "returns the stat aggregates with the user's currency" do
      expect(response).to have_http_status(:ok)
      expect(body).to include(
        "currency" => "TRY",
        "subunit_to_unit" => 100,
        "month_net_cents" => 300_00,
        "active_streaks" => 1,
        "open_todos" => 3,
        "overdue_count" => 1,
        "today_events_count" => 1,
        "habit_completion_pct" => 33
      )
    end

    it "returns the 7-day spending series" do
      expect(body["spending_7d"].length).to eq(7)
      expect(body["spending_7d"].first).to eq("date" => (today - 6.days).iso8601, "cents" => 0)
      expect(body["spending_7d"][4]["cents"]).to eq(80_00)
      expect(body["spending_7d"].last).to eq("date" => today.iso8601, "cents" => 120_00)
    end

    it "returns today's habits with completion state and streaks" do
      expect(body["today_habits"].map { |h| h["name"] }).to eq([ "A koşu", "B kitap" ])
      expect(body["today_habits"].first).to eq(
        "id" => Habit.find_by!(name: "A koşu").id, "name" => "A koşu", "color" => "#B8860B", "target_count" => 1,
        "completed_today" => true, "today_count" => 1, "current_streak" => 2
      )
      expect(body["today_habits"].last).to include(
        "id" => Habit.find_by!(name: "B kitap").id, "target_count" => 3,
        "completed_today" => false, "today_count" => 1, "current_streak" => 0
      )
    end

    it "returns open todos due within a week, ordered by due date" do
      expect(body["upcoming_todos"].map { |t| t["title"] }).to eq([ "Geciken", "Yakında" ])
      expect(body["upcoming_todos"].first).to include(
        "id" => Todo.find_by!(title: "Geciken").id, "overdue" => true, "priority" => "medium",
        "todo_list" => { "id" => TodoList.find_by!(name: "Ev").id, "name" => "Ev", "color" => "#B8860B" }
      )
      expect(body["upcoming_todos"].last).to include("overdue" => false, "priority" => "high")
    end

    it "returns only today's events" do
      expect(body["today_events"].map { |e| e["title"] }).to eq([ "Toplantı" ])
      expect(body["today_events"].first).to include(
        "id" => Event.find_by!(title: "Toplantı").id, "all_day" => false,
        "color" => "#B8860B", "duration_minutes" => 60
      )
      expect(body["today_events"].first["start_at"]).to start_with("2026-06-17T09:00")
    end

    it "returns the top 3 active goals by position" do
      expect(body["active_goals"]).to eq([
        { "id" => Goal.find_by!(name: "Hedef 1").id, "name" => "Hedef 1", "color" => "#123456",
          "progress_percent" => 25.0 },
        { "id" => Goal.find_by!(name: "Hedef 2").id, "name" => "Hedef 2", "color" => "#B8860B",
          "progress_percent" => 0 },
        { "id" => Goal.find_by!(name: "Hedef 3").id, "name" => "Hedef 3", "color" => "#B8860B",
          "progress_percent" => 0 }
      ])
    end

    it "returns the perfect day chain with the current streak" do
      expect(body["perfect_day"]).to eq(
        "chain" => [
          { "date" => (today - 1.day).iso8601, "status" => "perfect" },
          { "date" => today.iso8601, "status" => "partial" }
        ],
        "current_streak" => 1
      )
    end
  end

  it "expands recurring events into today and caps the list at 4" do
    create(:event, user: user, title: "Sabah sporu", recurring: true, recurrence_rule: "FREQ=DAILY",
           start_at: 10.days.ago.change(hour: 7))
    create(:event, user: user, title: "Eski tek seferlik", start_at: 10.days.ago.change(hour: 8))
    4.times { |i| create(:event, user: user, title: "Bugün #{i}", start_at: Time.current.change(hour: 9 + i)) }

    get api_v1_home_path, headers: auth

    body = JSON.parse(response.body)
    expect(body["today_events_count"]).to eq(5)
    expect(body["today_events"].length).to eq(4)
    expect(body["today_events"].map { |e| e["title"] }).to include("Sabah sporu")
    expect(body["today_events"].map { |e| e["title"] }).not_to include("Eski tek seferlik")
  end

  it "limits upcoming_todos to 6 due within a week" do
    8.times { |i| create(:todo, user: user, due_at: (i + 1).hours.from_now) }

    get api_v1_home_path, headers: auth

    body = JSON.parse(response.body)
    expect(body["open_todos"]).to eq(8)
    expect(body["upcoming_todos"].length).to eq(6)
  end

  context "with another user's data" do
    before do
      other = create(:user)
      other_account = create(:account, user: other)
      create(:transaction, :income, user: other, account: other_account, amount_cents: 900_00, date: today)
      create(:transaction, user: other, account: other_account, amount_cents: 50_00, date: today)
      create(:habit_log, habit: create(:habit, user: other), date: today, completed: true)
      create(:todo, user: other, due_at: 1.day.ago)
      create(:event, user: other, start_at: Time.current.change(hour: 9))
      create(:goal, user: other)
    end

    it "does not leak any of it" do
      get api_v1_home_path, headers: auth

      body = JSON.parse(response.body)
      expect(body).to include(
        "month_net_cents" => 0, "active_streaks" => 0, "open_todos" => 0,
        "overdue_count" => 0, "today_events_count" => 0, "habit_completion_pct" => 0
      )
      expect(body.values_at("today_habits", "upcoming_todos", "today_events", "active_goals")).to all(eq([]))
      expect(body["spending_7d"].sum { |d| d["cents"] }).to eq(0)
    end
  end
end
