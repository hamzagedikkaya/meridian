require 'rails_helper'

RSpec.describe "Search", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it "returns matching transactions" do
    create(:transaction, user: user, description: "Netflix subscription")
    get search_path, params: { q: "netflix" }, headers: { "Accept" => "application/json" }
    expect(response).to have_http_status(:success)
    body = JSON.parse(response.body)
    expect(body["results"].map { |r| r["type"] }).to include("Transaction")
  end

  it "matches Turkish letters in any case and reads % and _ literally, as the API search does" do
    create(:todo, user: user, title: "Şeker al a_b")
    create(:todo, user: user, title: "Tuz al axb")

    get search_path, params: { q: "şeker" }, headers: { "Accept" => "application/json" }
    expect(JSON.parse(response.body)["results"].map { |r| r["title"] }).to eq([ "Şeker al a_b" ])

    get search_path, params: { q: "a_b" }, headers: { "Accept" => "application/json" }
    expect(JSON.parse(response.body)["results"].map { |r| r["title"] }).to eq([ "Şeker al a_b" ])
  end

  def web_results(query)
    get search_path, params: { q: query }, headers: { "Accept" => "application/json" }
    JSON.parse(response.body)["results"]
  end

  # The command palette and GET /api/v1/search share GlobalSearch, so they
  # list the same rows in the same order (API section 13).
  it "finds a transaction by its note and a journal entry by its body, as the API does" do
    note_only = create(:transaction, user: user, description: "Market", note: "kahve parası")
    entry = create(:journal_entry, user: user, title: "Pazar")
    entry.update!(body_text: "Sabah kahvesi balkonda")

    titles = web_results("kahve").map { |row| row["title"] }

    expect(titles).to eq([ "Market", "Pazar" ])
    expect(web_results("kahve").map { |row| row["id"] }).to eq([ note_only.id, entry.id ])
  end

  it "lists the same rows in the same order as GET /api/v1/search" do
    create(:transaction, user: user, description: "Kahve eski", date: Date.current - 3)
    create(:transaction, user: user, description: "Kahve yeni", date: Date.current)
    create(:todo, user: user, title: "Kahve al", status: "done")
    create(:todo, user: user, title: "Kahve filtresi", status: "pending")
    create(:event, user: user, title: "Kahve buluşması", start_at: 2.days.from_now)
    create(:event, user: user, title: "Kahve tadımı", start_at: 5.days.from_now)
    create(:goal, user: user, name: "Kahve azalt")
    create(:habit, user: user, name: "Kahve yok")
    create(:subscription, user: user, name: "Kahve kulübü")

    web = web_results("kahve").map { |row| row["id"] }
    get api_v1_search_path, params: { q: "kahve" }, headers: { "Authorization" => "Bearer #{user.api_token}" }
    api = JSON.parse(response.body)["results"].map { |row| row["id"] }

    expect(web).to eq(api)
    expect(web.size).to eq(9)
  end

  it "formats a subscription's amount in its currency's own units" do
    gold = create(:account, user: user, currency: "GAU")
    create(:subscription, user: user, account: gold, name: "Altın birikimi", amount_cents: 5)
    create(:subscription, user: user, name: "Altın kulübü", amount_cents: 149_90)

    subtitles = web_results("altın").map { |row| row["subtitle"] }

    expect(subtitles).to contain_exactly("Monthly · 5 gr", "Monthly · ₺149.90")
  end

  it "returns empty for blank query" do
    get search_path, params: { q: "" }, headers: { "Accept" => "application/json" }
    body = JSON.parse(response.body)
    expect(body["results"]).to eq([])
  end
end
