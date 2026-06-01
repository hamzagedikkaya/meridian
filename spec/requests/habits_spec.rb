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

    it "renders both the 30-day and 84-day chains" do
      # Anchor completions at the oldest day of each window so chain trimming
      # leaves both chains at their full length (30 and 84).
      habit.habit_logs.create!(date: 29.days.ago.to_date, completed: true)
      habit.habit_logs.create!(date: 83.days.ago.to_date, completed: true)
      get habit_path(habit)
      expect(response).to have_http_status(:success)
      expect(response.body).to include('class="habit-chain"')
      # 30-day :lg chain + 84-day :xl chain = 114 outer <g> nodes.
      expect(response.body.scan(/class="chain-link chain-link--/).size).to eq(114)
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

    context "with target_count > 1" do
      let(:counter_habit) { create(:habit, user: user, target_count: 5) }

      it "checkbox toggle (no delta) jumps to target_count and marks completed" do
        patch toggle_today_habit_path(counter_habit)
        log = counter_habit.habit_logs.find_by(date: Date.current)
        expect(log.count).to eq(5)
        expect(log.completed).to be(true)
      end

      it "second checkbox toggle resets to zero, completed false" do
        patch toggle_today_habit_path(counter_habit)
        patch toggle_today_habit_path(counter_habit)
        log = counter_habit.habit_logs.find_by(date: Date.current)
        expect(log.count).to eq(0)
        expect(log.completed).to be(false)
      end

      it "?delta=+1 increments by one without flipping completed until target" do
        patch toggle_today_habit_path(counter_habit), params: { delta: 1 }
        log = counter_habit.habit_logs.find_by(date: Date.current)
        expect(log.count).to eq(1)
        expect(log.completed).to be(false)
      end

      it "reaching target via increments marks completed" do
        5.times { patch toggle_today_habit_path(counter_habit), params: { delta: 1 } }
        log = counter_habit.habit_logs.find_by(date: Date.current)
        expect(log.count).to eq(5)
        expect(log.completed).to be(true)
      end

      it "clamps increments at target_count" do
        6.times { patch toggle_today_habit_path(counter_habit), params: { delta: 1 } }
        expect(counter_habit.habit_logs.find_by(date: Date.current).count).to eq(5)
      end

      it "?delta=-1 decrements and flips completed back to false" do
        5.times { patch toggle_today_habit_path(counter_habit), params: { delta: 1 } }
        patch toggle_today_habit_path(counter_habit), params: { delta: -1 }
        log = counter_habit.habit_logs.find_by(date: Date.current)
        expect(log.count).to eq(4)
        expect(log.completed).to be(false)
      end

      it "clamps decrement at zero" do
        patch toggle_today_habit_path(counter_habit), params: { delta: -1 }
        expect(counter_habit.habit_logs.find_by(date: Date.current).count).to eq(0)
      end
    end
  end

  describe "interactive chain links on /habits" do
    it "adds chain-toggle controller only to today's link in the index row" do
      create(:habit, user: user)
      get habits_path
      # Per habit (1 here) there should be exactly one interactive link (today).
      expect(response.body.scan(/chain-link--interactive/).size).to eq(1)
      expect(response.body).to include(%(data-controller="chain-toggle"))
    end
  end
end
