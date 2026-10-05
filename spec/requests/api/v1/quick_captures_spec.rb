require "rails_helper"

RSpec.describe "Api::V1::QuickCaptures", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:auth) { { "Authorization" => "Bearer #{user.api_token}" } }

  def capture(text, **params)
    post api_v1_quick_captures_path, params: { text: text, **params }, headers: auth
    JSON.parse(response.body)
  end

  it "401s without a token" do
    post api_v1_quick_captures_path, params: { text: "süt al" }

    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)).to eq("error" => "unauthorized", "code" => "unauthorized")
  end

  describe "POST /api/v1/quick_captures" do
    it "captures '-250 kahve' as an expense on the first active account and returns it" do
      create(:account, user: user, name: "Archived", archived_at: Time.current)
      account = create(:account, user: user, name: "Cash")

      body = capture("-250 kahve")

      expect(response).to have_http_status(:created)
      transaction = user.transactions.sole
      expect(transaction).to have_attributes(kind: "expense", amount_cents: 25_000, account_id: account.id,
                                             description: "kahve", date: Date.current)
      expect(body).to include("saved" => true, "captured_type" => "transaction", "record_id" => transaction.id,
                              "summary" => "kahve", "message" => "Captured as transaction.")
      expect(body["record"]).to include("id" => transaction.id, "kind" => "expense", "amount_cents" => 25_000)
    end

    it "parses Turkish and English amounts with a sign and income with +" do
      create(:account, user: user)

      capture("-1.250,50 market")
      capture("+1,250.50 refund")

      expect(user.transactions.order(:id).pluck(:kind, :amount_cents)).to eq([ [ "expense", 125_050 ], [ "income", 125_050 ] ])
    end

    it "scales the amount by the account currency subunit (GAU → 1, not 100)" do
      create(:account, user: user, name: "Altın", currency: "GAU")

      capture("-5 altin")

      expect(response).to have_http_status(:created)
      expect(user.transactions.sole).to have_attributes(kind: "expense", amount_cents: 5)
    end

    describe "account_id" do
      let!(:oldest) { create(:account, user: user, name: "Cash") }
      let(:card) { create(:account, user: user, name: "Card") }

      it "records money on the chosen account, archived included, and on the oldest active one without it" do
        archived = create(:account, user: user, archived_at: Time.current)

        expect(capture("-85 kahve", account_id: card.id)["record"]["account"]).to include("id" => card.id, "name" => "Card")
        expect(capture("+10 iade", account_id: archived.id.to_s)["record"]["account"]["id"]).to eq(archived.id)
        expect(capture("-5 su", account_id: "")["record"]["account"]["id"]).to eq(oldest.id)
        expect(user.transactions.order(:id).pluck(:account_id)).to eq([ card.id, archived.id, oldest.id ])
      end

      it "404s for another user's or a missing account and 422s for an id that is not a whole number" do
        capture("-85 kahve", account_id: create(:account).id)
        expect(response).to have_http_status(:not_found)

        body = capture("süt al", account_id: "abc")
        expect(response).to have_http_status(:unprocessable_content)
        expect(body).to include("code" => "invalid_parameter", "param" => "account_id")
        expect(user.transactions.count + user.todos.count).to eq(0)
      end
    end

    it "saves a number without a sign as a todo, not money" do
      create(:account, user: user)

      body = capture("3 yumurta al")

      expect(body).to include("saved" => true, "captured_type" => "todo")
      expect(user.transactions).to be_empty
    end

    it "422s with code no_account when the user has no active account" do
      body = capture("-250 kahve")

      expect(response).to have_http_status(:unprocessable_content)
      expect(body).to eq("errors" => { "text" => [ "Create your first account" ] }, "code" => "no_account")
    end

    it "422s with code invalid_amount and a reason for amounts it cannot store" do
      create(:account, user: user, currency: "GAU")

      body = capture("-1,5 altın")

      expect(response).to have_http_status(:unprocessable_content)
      expect(body).to include("code" => "invalid_amount", "reason" => "too_precise")
      expect(body["errors"]["text"]).to eq([ "GAU amounts can't have that many decimal places." ])
      expect(user.transactions).to be_empty
    end

    it "logs 'habit: X' and returns the log" do
      habit = create(:habit, user: user, name: "Koşu")

      body = capture("habit: koşu")

      expect(response).to have_http_status(:created)
      log = habit.habit_logs.sole
      expect(log).to have_attributes(completed: true, count: 1, date: Date.current)
      expect(body).to include("saved" => true, "captured_type" => "habit_log", "record_id" => log.id, "summary" => "Koşu")
      expect(body["record"]).to eq("id" => log.id, "habit_id" => habit.id, "date" => Date.current.iso8601,
                                   "count" => 1, "completed" => true)
    end

    it "accepts 'alışkanlık:' as an alias of 'habit:'" do
      habit = create(:habit, user: user, name: "Okuma")

      capture("Alışkanlık: okuma")

      expect(response).to have_http_status(:created)
      expect(habit.habit_logs.count).to eq(1)
    end

    it "422s with code unknown_habit and the name for a habit the user does not have" do
      other_habit = create(:habit, name: "Read")

      body = capture("habit: Read")

      expect(response).to have_http_status(:unprocessable_content)
      expect(body).to include("code" => "unknown_habit", "name" => "Read")
      expect(body["errors"]["text"]).to eq([ "Habit 'Read' not found. Create it?" ])
      expect(other_habit.habit_logs.count).to eq(0)
    end

    it "answers an event-like text with saved: false and a prefill, creating nothing" do
      body = capture("yarın 15:00 dişçi")

      expect(response).to have_http_status(:ok)
      expect([ Event.count, Todo.count ]).to eq([ 0, 0 ])
      expect(body).to include("saved" => false, "captured_type" => "event_suggestion",
                              "record_id" => nil, "summary" => "yarın 15:00 dişçi")
      expect(body["suggestion"]).to eq(
        "title" => "dişçi", "date" => (Date.current + 1).iso8601, "time" => "15:00",
        "start_at" => Time.zone.parse("#{Date.current + 1} 15:00").as_json, "all_day" => false, "keyword" => "yarın"
      )
    end

    it "reads an hour with a Turkish case ending, and a capitalized day word, into the suggestion" do
      user.update!(timezone: "Istanbul")

      body = travel_to(Time.utc(2026, 10, 7, 9)) { capture("Çarşamba 9'da dişçi") } # a Wednesday

      expect(response).to have_http_status(:ok)
      expect(body["suggestion"]).to eq(
        "title" => "dişçi", "date" => "2026-10-14", "time" => "09:00",
        "start_at" => "2026-10-14T09:00:00.000+03:00", "all_day" => false, "keyword" => "Çarşamba"
      )
    end

    it "saves a bare 'pazar' (market) and a day word with a suffix as todos" do
      [ "pazar alışverişi", "Cuma'ya kadar rapor" ].each do |text|
        body = capture(text)

        expect(response).to have_http_status(:created)
        expect(body).to include("saved" => true, "captured_type" => "todo", "summary" => text)
      end
      expect(user.todos.order(:id).pluck(:title)).to eq([ "pazar alışverişi", "Cuma'ya kadar rapor" ])
    end

    it "suggests an all-day event when no time is given" do
      body = capture("Lunch with Ahmet tomorrow")

      expect(body["suggestion"]).to include("title" => "Lunch with Ahmet", "time" => nil, "start_at" => nil, "all_day" => true)
    end

    it "saves the text as a todo when the client resends with as=todo" do
      body = capture("yarın dişçi", as: "todo")

      expect(response).to have_http_status(:created)
      expect(body).to include("saved" => true, "captured_type" => "todo")
      expect(user.todos.sole.title).to eq("yarın dişçi")
    end

    it "422s with code invalid_parameter for an unknown as" do
      body = capture("süt al", as: "event")

      expect(response).to have_http_status(:unprocessable_content)
      expect(body).to include("code" => "invalid_parameter", "param" => "as")
      expect(Todo.count).to eq(0)
    end

    # The app sends as only as "todo"; a blank value is not read as "let the
    # rules decide" (which would answer an event suggestion here).
    it "422s with code invalid_parameter for a blank as, as the contract says" do
      post api_v1_quick_captures_path, params: { text: "yarın 15:00 kontrol", as: "" }, headers: auth, as: :json
      body = JSON.parse(response.body)

      expect(response).to have_http_status(:unprocessable_content)
      expect(body).to include("code" => "invalid_parameter", "param" => "as")
      expect(Todo.count).to eq(0)
    end

    it "lets the rules decide when as is null" do
      post api_v1_quick_captures_path, params: { text: "yarın 15:00 kontrol", as: nil }, headers: auth, as: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["captured_type"]).to eq("event_suggestion")
    end

    it "captures plain text as a medium-priority todo and returns it" do
      body = capture("süt al")

      expect(response).to have_http_status(:created)
      todo = user.todos.sole
      expect(todo).to have_attributes(title: "süt al", priority: "medium", status: "pending")
      expect(body).to include("saved" => true, "captured_type" => "todo", "record_id" => todo.id, "summary" => "süt al")
      expect(body["record"]).to include("id" => todo.id, "title" => "süt al", "status" => "pending")
    end

    it "422s with validation_failed when the todo itself is invalid" do
      body = capture("x" * 201)

      expect(response).to have_http_status(:unprocessable_content)
      expect(body["code"]).to eq("validation_failed")
      expect(body["details"]["title"]).to eq([ { "error" => "too_long", "count" => 200 } ])
    end

    it "422s with code empty for blank text" do
      body = capture("   ")

      expect(response).to have_http_status(:unprocessable_content)
      expect(body).to eq("errors" => { "text" => [ "Empty input" ] }, "code" => "empty")
    end

    it "words messages in the user's language" do
      user.update!(locale: "tr")

      expect(capture("habit: Yok")["errors"]["text"]).to eq([ "'Yok' alışkanlığı yok. Oluşturulsun mu?" ])
      expect(capture("süt al")["message"]).to eq("Görev olarak yakalandı: süt al")
    end
  end
end
