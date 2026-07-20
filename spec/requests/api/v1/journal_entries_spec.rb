require "rails_helper"

RSpec.describe "Api::V1::JournalEntries", type: :request do
  let(:user) { create(:user) }
  let(:auth) { { "Authorization" => "Bearer #{user.api_token}" } }

  it "401s without a token" do
    get api_v1_journal_entries_path

    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)["error"]).to eq("unauthorized")
  end

  describe "GET /api/v1/journal_entries" do
    it "returns entries in the default 30d range with streak and mood counts" do
      create(:journal_entry, user: user, date: Date.current, title: "Today", mood: "great")
      create(:journal_entry, user: user, date: Date.current - 1, title: "Yesterday", mood: "good")
      create(:journal_entry, user: user, date: Date.current - 40, title: "Old", mood: "bad")
      create(:journal_entry, title: "Someone else's")

      get api_v1_journal_entries_path, headers: auth

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["entries"].map { |e| e["title"] }).to eq([ "Today", "Yesterday" ])
      expect(body["meta"]).to include("entries_count" => 2, "journal_streak" => 2, "range" => "30d")
      expect(body["meta"]["mood_counts"]).to eq(
        "great" => 1, "good" => 1, "neutral" => 0, "bad" => 0, "awful" => 0
      )
    end

    it "widens to all entries with range=all" do
      create(:journal_entry, user: user, date: Date.current - 40, title: "Old")

      get api_v1_journal_entries_path(range: "all"), headers: auth

      body = JSON.parse(response.body)
      expect(body["entries"].map { |e| e["title"] }).to eq([ "Old" ])
      expect(body["meta"]["range"]).to eq("all")
    end

    it "narrows with range=7d and falls back to 30d for unknown ranges" do
      create(:journal_entry, user: user, date: Date.current - 10, title: "Ten days ago")

      get api_v1_journal_entries_path(range: "7d"), headers: auth
      expect(JSON.parse(response.body)["entries"]).to be_empty

      get api_v1_journal_entries_path(range: "bogus"), headers: auth
      expect(JSON.parse(response.body)["meta"]["range"]).to eq("30d")
    end

    it "truncates the rich-text body to 200 plain-text chars" do
      create(:journal_entry, user: user, body: "a" * 300)

      get api_v1_journal_entries_path, headers: auth

      plain = JSON.parse(response.body)["entries"].first["body_plain"]
      expect(plain.length).to eq(200)
      expect(plain).to end_with("...")
      expect(plain).to start_with("aaa")
    end
  end

  describe "GET /api/v1/journal_entries/:id" do
    it "returns the full entry with body_html and gratitude" do
      entry = create(:journal_entry, user: user, mood: "good", energy_level: 4,
                     body: "Hello <strong>world</strong>", gratitude: "Coffee", tags: "sea, sun")

      get api_v1_journal_entry_path(entry), headers: auth

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)["entry"]
      expect(json).to include(
        "id" => entry.id, "mood" => "good", "mood_emoji" => "🙂",
        "energy_level" => 4, "gratitude" => "Coffee", "has_gratitude" => true,
        "tags" => [ "sea", "sun" ]
      )
      expect(json["body_html"]).to include("<strong>world</strong>")
    end

    it "404s for another user's entry" do
      entry = create(:journal_entry)

      get api_v1_journal_entry_path(entry), headers: auth

      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)["error"]).to eq("not_found")
    end
  end

  describe "POST /api/v1/journal_entries" do
    it "creates an entry from flat params" do
      expect {
        post api_v1_journal_entries_path,
             params: { date: Date.current.iso8601, title: "New day", body: "It was fine",
                       mood: "neutral", energy_level: 3, weather: "sunny", tags: "work, gym" },
             headers: auth
      }.to change(user.journal_entries, :count).by(1)

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)["entry"]
      expect(json).to include("title" => "New day", "mood" => "neutral", "weather" => "sunny")
      expect(json["tags"]).to eq([ "work", "gym" ])
    end

    it "422s with field errors for an invalid mood" do
      post api_v1_journal_entries_path, params: { date: Date.current.iso8601, mood: "amazing" }, headers: auth

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["errors"]).to have_key("mood")
    end
  end

  describe "PATCH /api/v1/journal_entries/:id" do
    it "updates the entry" do
      entry = create(:journal_entry, user: user, title: "Before")

      patch api_v1_journal_entry_path(entry), params: { title: "After" }, headers: auth

      expect(response).to have_http_status(:ok)
      expect(entry.reload.title).to eq("After")
    end

    it "404s for another user's entry" do
      entry = create(:journal_entry, title: "Untouchable")

      patch api_v1_journal_entry_path(entry), params: { title: "Hacked" }, headers: auth

      expect(response).to have_http_status(:not_found)
      expect(entry.reload.title).to eq("Untouchable")
    end
  end

  describe "DELETE /api/v1/journal_entries/:id" do
    it "destroys the entry" do
      entry = create(:journal_entry, user: user)

      expect {
        delete api_v1_journal_entry_path(entry), headers: auth
      }.to change(user.journal_entries, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end

    it "404s for another user's entry" do
      entry = create(:journal_entry)

      expect {
        delete api_v1_journal_entry_path(entry), headers: auth
      }.not_to change(JournalEntry, :count)

      expect(response).to have_http_status(:not_found)
    end
  end
end
