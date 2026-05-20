require 'rails_helper'

RSpec.describe "Habits", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /habits" do
    it "renders" do
      get habits_path
      expect(response).to have_http_status(:success)
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
  end
end
