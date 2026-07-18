require "rails_helper"

RSpec.describe "Api::V1::QuickCaptures", type: :request do
  let(:user) { create(:user) }
  let(:auth) { { "Authorization" => "Bearer #{user.api_token}" } }

  it "401s without a token" do
    post api_v1_quick_captures_path, params: { text: "süt al" }

    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)["error"]).to eq("unauthorized")
  end

  describe "POST /api/v1/quick_captures" do
    it "captures '-250 kahve' as an expense on the first active account" do
      create(:account, user: user, name: "Archived", archived_at: Time.current)
      account = create(:account, user: user, name: "Cash")

      expect {
        post api_v1_quick_captures_path, params: { text: "-250 kahve" }, headers: auth
      }.to change(user.transactions, :count).by(1)

      expect(response).to have_http_status(:created)
      transaction = user.transactions.last
      expect(transaction).to have_attributes(
        kind: "expense", amount_cents: 25_000, account_id: account.id,
        description: "kahve", date: Date.current
      )
      expect(JSON.parse(response.body)).to eq(
        "captured_type" => "transaction", "record_id" => transaction.id, "summary" => "kahve"
      )
    end

    it "scales the amount by the account currency subunit (GAU → 1, not 100)" do
      create(:account, user: user, name: "Altın", currency: "GAU")

      post api_v1_quick_captures_path, params: { text: "-5 altin" }, headers: auth

      expect(response).to have_http_status(:created)
      expect(user.transactions.last).to have_attributes(kind: "expense", amount_cents: 5)
    end

    it "captures '+1000 maaş' as income" do
      create(:account, user: user)

      post api_v1_quick_captures_path, params: { text: "+1000 maaş" }, headers: auth

      expect(user.transactions.last).to have_attributes(kind: "income", amount_cents: 100_000)
    end

    it "422s for a numeric capture when the user has no active account" do
      post api_v1_quick_captures_path, params: { text: "-250 kahve" }, headers: auth

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["errors"]["text"]).to be_present
    end

    it "captures 'habit: X' as a completed habit log" do
      habit = create(:habit, user: user, name: "Koşu")

      expect {
        post api_v1_quick_captures_path, params: { text: "habit: koşu" }, headers: auth
      }.to change(habit.habit_logs, :count).by(1)

      expect(response).to have_http_status(:created)
      log = habit.habit_logs.last
      expect(log).to have_attributes(completed: true, count: 1, date: Date.current)
      expect(JSON.parse(response.body)).to eq(
        "captured_type" => "habit_log", "record_id" => log.id, "summary" => "Koşu"
      )
    end

    it "does not log another user's habit with the same name" do
      other_habit = create(:habit, name: "Read")

      post api_v1_quick_captures_path, params: { text: "habit: Read" }, headers: auth

      expect(response).to have_http_status(:unprocessable_entity)
      expect(other_habit.habit_logs.count).to eq(0)
    end

    it "suggests an event for date-like text without creating a record" do
      post api_v1_quick_captures_path, params: { text: "yarın dişçi" }, headers: auth

      expect(Event.count).to eq(0)
      expect(Todo.count).to eq(0)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq(
        "captured_type" => "event_suggestion", "record_id" => nil, "summary" => "yarın dişçi"
      )
    end

    it "captures plain text as a medium-priority todo" do
      expect {
        post api_v1_quick_captures_path, params: { text: "süt al" }, headers: auth
      }.to change(user.todos, :count).by(1)

      expect(response).to have_http_status(:created)
      todo = user.todos.last
      expect(todo).to have_attributes(title: "süt al", priority: "medium", status: "pending")
      expect(JSON.parse(response.body)).to eq(
        "captured_type" => "todo", "record_id" => todo.id, "summary" => "süt al"
      )
    end

    it "422s for blank text" do
      post api_v1_quick_captures_path, params: { text: "   " }, headers: auth

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["errors"]["text"]).to be_present
    end
  end
end
