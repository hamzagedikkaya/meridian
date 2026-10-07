require "rails_helper"

RSpec.describe "Api::V1::Search", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:auth) { { "Authorization" => "Bearer #{user.api_token}" } }
  let(:account) { create(:account, user: user, name: "Wallet") }

  def search(query)
    get api_v1_search_path, params: { q: query }, headers: auth
    JSON.parse(response.body)
  end

  def results_for(query, type = nil)
    results = search(query)["results"]
    type ? results.select { |result| result["type"] == type } : results
  end

  before { travel_to Time.zone.local(2026, 10, 4, 12, 30) }
  after { travel_back }

  it "401s without a token" do
    get api_v1_search_path, params: { q: "kahve" }

    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)).to eq("error" => "unauthorized", "code" => "unauthorized")
  end

  describe "the query" do
    it "422s with query_too_short below 2 characters, spaces not counted, in the user's language" do
      user.update!(locale: "tr")

      expect(search(" k ")).to eq(
        "errors" => { "q" => [ "Aramak için en az 2 karakter yaz." ] }, "code" => "query_too_short", "min_length" => 2
      )
      expect(response).to have_http_status(:unprocessable_content)
      get api_v1_search_path, headers: auth
      expect(JSON.parse(response.body)["code"]).to eq("query_too_short")
    end

    it "422s with invalid_parameter for a list or more than 100 characters" do
      get api_v1_search_path, params: { q: [ "kahve" ] }, headers: auth
      expect(JSON.parse(response.body)).to include("code" => "invalid_parameter", "param" => "q")

      expect(search("a" * 101)).to include("code" => "invalid_parameter", "param" => "q")
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "echoes the stripped query and reads % and _ literally" do
      create(:transaction, user: user, account: account, description: "100% iade")
      create(:transaction, user: user, account: account, description: "1000 iade")

      expect(search(" 0% ")).to include("query" => "0%")
      expect(search(" 0% ")["results"].map { |result| result["title"] }).to eq([ "100% iade" ])
      expect(results_for("__")).to eq([])
    end
  end

  describe "results" do
    it "groups every type in a fixed order, matching any case, and leaves other users' records out" do
      create(:subscription, user: user, account: account, name: "Kahve kulübü")
      create(:habit, user: user, name: "Kahve yok")
      create(:goal, user: user, name: "Kahve makinesi")
      create(:journal_entry, user: user, title: "Kahve günü")
      create(:event, user: user, title: "Kahve buluşması")
      create(:todo, user: user, title: "KAHVE al")
      create(:transaction, user: user, account: account, description: "kahve")
      create(:transaction, description: "Kahve")
      create(:todo, title: "Kahve")
      create(:habit, name: "Kahve")

      expect(results_for("Kahve").map { |result| result["type"] }).to eq(Api::V1::SearchController::TYPES)
    end

    it "ignores the case of Turkish letters, reading I, İ, ı and i as one letter, but keeps accents" do
      create(:todo, user: user, title: "İstanbul'a bilet al")
      create(:event, user: user, title: "IŞIK gösterisi")
      create(:habit, user: user, name: "Şeker yok")
      create(:habit, user: user, name: "Koşu")

      expect(results_for("istanbul").map { |result| result["title"] }).to eq([ "İstanbul'a bilet al" ])
      expect(results_for("ışık").map { |result| result["title"] }).to eq([ "IŞIK gösterisi" ])
      expect(results_for("ŞEKER").map { |result| result["title"] }).to eq([ "Şeker yok" ])
      expect(results_for("kosu")).to eq([])
    end

    it "returns at most 5 of each type, newest transactions first" do
      transactions = (1..6).map { |day| create(:transaction, user: user, account: account, description: "Market", date: Date.new(2026, 9, day)) }

      ids = results_for("market", "transaction").map { |result| result["id"] }

      expect(ids.size).to eq(5)
      expect(ids).not_to include(transactions.first.id)
    end
  end

  describe "titles and subtitles" do
    it "describes a transaction by date, accounts and signed amount" do
      create(:transaction, user: user, account: account, description: "Kahve", amount_cents: 1_250_50, date: Date.new(2026, 10, 3))
      create(:transaction, :income, user: user, account: create(:account, user: user, name: "Kasa", currency: "GAU"),
                                    description: "Altın kahve", amount_cents: 12, date: Date.new(2026, 10, 2))
      create(:transaction, :transfer, user: user, account: account, related_account: create(:account, user: user, name: "Bank"),
                                      description: nil, note: "kahve parası", amount_cents: 300_00, date: Date.new(2026, 10, 1))

      expect(results_for("kahve")).to eq([
        { "type" => "transaction", "id" => user.transactions.find_by(amount_cents: 1_250_50).id, "title" => "Kahve", "subtitle" => "3 Oct 2026 · Wallet · −₺1,250.50" },
        { "type" => "transaction", "id" => user.transactions.find_by(amount_cents: 12).id, "title" => "Altın kahve", "subtitle" => "2 Oct 2026 · Kasa · +12 gr" },
        { "type" => "transaction", "id" => user.transactions.find_by(amount_cents: 300_00).id, "title" => "Transfer", "subtitle" => "1 Oct 2026 · Wallet → Bank · ₺300.00" }
      ])
    end

    it "words subtitles in Turkish for a Turkish user" do
      user.update!(locale: "tr")
      create(:transaction, user: user, account: account, description: "Kahve", amount_cents: 1_250_50, date: Date.new(2026, 10, 3))
      create(:todo, user: user, title: "Kahve al", due_at: Time.zone.local(2026, 10, 5, 23, 59, 59))

      expect(results_for("kahve").map { |result| result["subtitle"] }).to eq([ "3 Eki 2026 · Wallet · −₺1.250,50", "Bekliyor · Son gün 5 Eki 2026" ])
    end

    it "lists open todos before closed ones" do
      done = create(:todo, user: user, title: "Süt al", status: "done")
      open = create(:todo, user: user, title: "Süt iç", created_at: 2.days.ago)

      expect(results_for("süt").map { |result| [ result["id"], result["subtitle"] ] }).to eq([ [ open.id, "Pending" ], [ done.id, "Done" ] ])
    end

    it "shows an event's start in the user's time zone, a date for an all-day one, and its location" do
      user.update!(timezone: "Istanbul")
      create(:event, user: user, title: "Dişçi", start_at: Time.utc(2026, 10, 6, 12), location: "Kadıköy")
      create(:event, user: user, title: "Dişçi günü", all_day: true, start_at: Time.utc(2026, 10, 5))

      expect(results_for("dişçi").map { |result| result["subtitle"] }).to eq([ "6 Oct 2026 15:00 · Kadıköy", "5 Oct 2026" ])
    end

    it "finds a journal entry by its body text but not by its markup, titled by its first line when untitled" do
      entry = create(:journal_entry, user: user, title: nil, date: Date.new(2026, 10, 3))
      entry.update!(body_text: "Sabah kahvesi\nSonra yürüyüş")

      expect(results_for("kahvesi")).to eq([ { "type" => "journal_entry", "id" => entry.id, "title" => "Sabah kahvesi", "subtitle" => "3 Oct 2026" } ])
      expect(results_for("div")).to eq([])
      expect(results_for("yürüyüş").map { |result| result["id"] }).to eq([ entry.id ])
    end

    it "gives a goal's progress or status, a habit's frequency, streak and archive, a subscription's charge" do
      create(:goal, user: user, name: "Tatil", target_value: 300, current_value: 100)
      create(:goal, user: user, name: "Tatil 2025", status: "achieved", target_value: 100, current_value: 100)
      habit = create(:habit, user: user, name: "Tatil yürüyüşü")
      create(:habit_log, habit: habit, date: Date.current, completed: true, count: 1)
      create(:habit, user: user, name: "Tatil günlüğü", frequency: "weekly", archived_at: Time.current)
      create(:subscription, user: user, account: account, name: "Tatil fonu", amount_cents: 99_99, next_charge_on: Date.new(2026, 10, 15))
      create(:subscription, user: user, account: account, name: "Tatil kulübü", active: false, frequency: "yearly")

      expect(results_for("tatil").map { |result| result["subtitle"] }).to eq([
        "33% complete", "Achieved", "Daily · 1-day streak", "Weekly · Archived",
        "Monthly · ₺99.99 · Next 15 Oct 2026", "Yearly · ₺100.00 · Inactive"
      ])
    end

    it "shows a goal's current status and progress, not the stored ones, and writes nothing" do
      goal = create(:goal, user: user, name: "Kumbara", target_type: "financial", related: account,
                           target_value: 10, current_value: 20, status: "achieved")

      expect(results_for("kumbara").map { |result| result["subtitle"] }).to eq([ "0% complete" ])
      expect(goal.reload).to have_attributes(status: "achieved", current_value: 20)

      # Stored as active, achieved since: listed after the active one.
      create(:goal, user: user, name: "Fon", target_type: "financial", related: account, target_value: 10, current_value: 0)
      create(:goal, user: user, name: "Fon 2", target_value: 5, current_value: 1)
      create(:transaction, :income, user: user, account: account, amount_cents: 20_00)
      expect(results_for("fon").map { |result| [ result["title"], result["subtitle"] ] }).to eq([ [ "Fon 2", "20% complete" ], [ "Fon", "Achieved" ] ])
    end
  end
end
