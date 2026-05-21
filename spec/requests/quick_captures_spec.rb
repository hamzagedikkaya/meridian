require 'rails_helper'

RSpec.describe "QuickCaptures", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "POST /quick_captures" do
    it "creates a todo for free text" do
      expect { post quick_captures_path, params: { text: "Buy milk" } }
        .to change(Todo, :count).by(1)
    end

    it "creates a transaction for numeric input" do
      create(:account, user: user)
      expect { post quick_captures_path, params: { text: "-42.50 Lunch" } }
        .to change(Transaction, :count).by(1)
    end

    it "creates an income transaction when prefixed with +" do
      create(:account, user: user)
      post quick_captures_path, params: { text: "+1000 Salary" }
      expect(Transaction.last.kind).to eq("income")
    end

    it "rejects empty input" do
      post quick_captures_path, params: { text: "" }
      expect(flash[:alert]).to be_present
    end

    it "logs a habit when the text starts with 'habit:'" do
      habit = create(:habit, user: user, name: "Read")
      expect {
        post quick_captures_path, params: { text: "habit: Read" }
      }.to change { habit.habit_logs.count }.by(1)
      expect(habit.habit_logs.last.completed).to be(true)
    end

    it "redirects to new habit when habit name is unknown" do
      post quick_captures_path, params: { text: "habit: Unknown" }
      expect(response).to redirect_to(/habits\/new/)
    end

    it "routes a date-like text toward event creation" do
      post quick_captures_path, params: { text: "Lunch with Ahmet yarın" }
      expect(response).to redirect_to(/events\/new/)
    end
  end
end
