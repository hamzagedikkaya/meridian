require 'rails_helper'

RSpec.describe "Habits", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /habits" do
    it "renders" do
      get habits_path
      expect(response).to have_http_status(:success)
    end

    it "renders a mini chain for each habit" do
      create(:habit, user: user)
      create(:habit, user: user)
      get habits_path
      # Each habit row chain + the perfect-day chain at the top.
      expect(response.body.scan(/class="habit-chain"/).size).to be >= 3
    end

    it "renders the perfect-day widget when at least one habit exists" do
      create(:habit, user: user, created_at: 5.days.ago)
      get habits_path
      expect(response.body).to include(I18n.t("pages.home.perfect_days"))
    end
  end

  describe "GET /habits/:id" do
    let(:habit) { create(:habit, user: user) }

    it "renders the 30-link chain" do
      get habit_path(habit)
      expect(response).to have_http_status(:success)
      expect(response.body).to include('class="habit-chain"')
      # 30 day window → 30 outer <g class="chain-link chain-link--..."> nodes.
      expect(response.body.scan(/class="chain-link chain-link--/).size).to eq(30)
    end
  end

  describe "POST /habits" do
    it "creates a habit" do
      expect { post habits_path, params: { habit: { name: "Test", frequency: "daily", target_count: 1 } } }
        .to change(Habit, :count).by(1)
    end
  end

  describe "PATCH /habits/:id/toggle_today" do
    let(:habit) { create(:habit, user: user) }

    it "toggles today's log to completed" do
      patch toggle_today_habit_path(habit)
      expect(habit.habit_logs.find_by(date: Date.current).completed).to be(true)
    end

    it "toggles back to false on second call" do
      patch toggle_today_habit_path(habit)
      patch toggle_today_habit_path(habit)
      expect(habit.habit_logs.find_by(date: Date.current).completed).to be(false)
    end

    it "responds with turbo-stream replacements for row, perfect-day widget, today progress and dashboard row" do
      patch toggle_today_habit_path(habit), headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include(%(target="index_row_habit_#{habit.id}"))
      expect(response.body).to include(%(target="perfect_day_widget"))
      expect(response.body).to include(%(target="habits_today_progress"))
      expect(response.body).to include(%(target="dashboard_habit_#{habit.id}"))
    end
  end
end
