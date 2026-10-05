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

    it "routes a date-like text toward event creation with the parsed title, date and time" do
      post quick_captures_path, params: { text: "Lunch with Ahmet yarın 13:00" }

      expect(response).to redirect_to(new_event_path(date: (Date.current + 1).iso8601, time: "13:00",
                                                     event: { title: "Lunch with Ahmet" }))
      expect(Event.count + Todo.count).to eq(0)
    end

    it "prefills the new-habit form with the unknown name" do
      post quick_captures_path, params: { text: "habit: Unknown" }
      expect(response).to redirect_to(new_habit_path(habit: { name: "Unknown" }))
    end

    it "saves a number without a sign as a todo" do
      create(:account, user: user)

      expect { post quick_captures_path, params: { text: "3 yumurta al" } }.to change(Todo, :count).by(1)
      expect(Transaction.count).to eq(0)
    end

    it "alerts instead of guessing an unreadable amount" do
      create(:account, user: user)

      expect { post quick_captures_path, params: { text: "-1.25.0 market" } }.not_to change(Transaction, :count)
      expect(flash[:alert]).to eq(I18n.t("quick_capture.invalid_amount.unreadable"))
    end

    it "alerts with the validation errors when the todo cannot be saved" do
      expect { post quick_captures_path, params: { text: "x" * 201 } }.not_to change(Todo, :count)
      expect(flash[:alert]).to include("Title")
    end
  end
end
