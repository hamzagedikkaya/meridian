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

    it "adds journal_streak_weeks, over all entries whatever the range, the user's only" do
      create(:journal_entry, user: user, date: Date.current)
      create(:journal_entry, user: user, date: Date.current - 7)
      create(:journal_entry, user: user, date: Date.current - 28)
      create(:journal_entry, date: Date.current - 14)

      get api_v1_journal_entries_path(range: "1d"), headers: auth

      expect(JSON.parse(response.body)["meta"]).to include("journal_streak" => 1, "journal_streak_weeks" => 2)
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

    it "dates an entry sent without a date, or with a null one, on the user's today" do
      post api_v1_journal_entries_path, params: { title: "No date" }, headers: auth

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["entry"]["date"]).to eq(Date.current.iso8601)

      post api_v1_journal_entries_path, params: { title: "Null date", date: nil }, headers: auth, as: :json

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["entry"]["date"]).to eq(Date.current.iso8601)
    end

    it "422s with validation_failed for a date that was sent but cannot be read, saving nothing" do
      [ "2026-02-30", "garbage", "" ].each do |date|
        post api_v1_journal_entries_path, params: { title: "Bad date", date: date }, headers: auth, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        body = JSON.parse(response.body)
        expect(body).to include("code" => "validation_failed"), "for #{date.inspect}"
        expect(body["details"]["date"]).to eq([ { "error" => "blank" } ])
      end
      expect(user.journal_entries).to be_empty
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

  # G4: the whole body, plain-text writes, keeping the web's formatting.
  describe "editable body" do
    def body = JSON.parse(response.body)

    def patch_entry(entry, params)
      patch api_v1_journal_entry_path(entry), params: params, headers: auth, as: :json
      body
    end

    let(:web_html) do
      "<div>Sabah <strong>erken</strong> kalktım.<br><br>Liste:</div><ul><li>koşu</li><li>kahve</li></ul>"
    end

    describe "GET /api/v1/journal_entries/:id" do
      it "returns the whole body as text and as HTML, nothing cut" do
        long = ("Uzun bir paragraf. " * 30).strip
        entry = create(:journal_entry, user: user, body: "<div>#{long}<br><br>İkinci paragraf<br>ve bir satır</div>")

        get api_v1_journal_entry_path(entry), headers: auth

        json = body["entry"]
        expect(json["body_text"]).to eq("#{long}\n\nİkinci paragraf\nve bir satır")
        expect(json["body_plain"]).to eq(json["body_text"])
        expect(json["body_html"]).to include(long, "<br><br>İkinci paragraf<br>ve bir satır")
        expect(json).to include("body_format" => "plain", "body_formatting" => [])
        expect(json["updated_at"]).to be_present
      end

      it "keeps the 200-character preview in the list" do
        create(:journal_entry, user: user, body: "<div>#{"a" * 300}</div>")

        get api_v1_journal_entries_path, headers: auth

        expect(body["entries"].first["body_plain"].length).to eq(200)
        expect(body["entries"].first).not_to have_key("body_text")
      end

      it "reports formatting from the web that plain text cannot hold" do
        entry = create(:journal_entry, user: user, body: web_html)

        get api_v1_journal_entry_path(entry), headers: auth

        json = body["entry"]
        expect(json).to include("body_format" => "rich", "body_formatting" => [ "bold", "list" ])
        expect(json["body_text"]).to eq("Sabah erken kalktım.\n\nListe:\n• koşu\n• kahve")
        expect(json["body_html"]).to include("<strong>erken</strong>", "<li>koşu</li>")
      end

      it "reads paragraphs and line breaks of every plain shape the body can have" do
        {
          "<p>Bir</p><p>İki<br>Üç</p>" => "Bir\n\nİki\nÜç",
          "<div>Bir</div><div>İki</div>" => "Bir\nİki",
          "Eski uygulama\n\nmetni" => "Eski uygulama\n\nmetni"
        }.each do |html, text|
          entry = create(:journal_entry, user: user, body: html)
          get api_v1_journal_entry_path(entry), headers: auth
          expect(body["entry"]).to include("body_text" => text, "body_format" => "plain"), "for #{html.inspect}"
        end
      end

      it "returns an empty body as \"\"" do
        entry = create(:journal_entry, user: user)

        get api_v1_journal_entry_path(entry), headers: auth

        expect(body["entry"]).to include("body_text" => "", "body_plain" => "", "body_html" => "",
                                         "body_format" => "plain", "body_formatting" => [])
      end
    end

    describe "POST /api/v1/journal_entries with body_text" do
      it "stores paragraphs and line breaks, HTML escaped, and reads back the same text" do
        text = "İlk satır\r\nikinci <b>kalın değil</b> & \"tırnak\"\r\n\r\n\r\nYeni paragraf  "

        post api_v1_journal_entries_path, params: { title: "Metin", body_text: text }, headers: auth, as: :json

        expect(response).to have_http_status(:created)
        json = body["entry"]
        expect(json["body_text"]).to eq("İlk satır\nikinci <b>kalın değil</b> & \"tırnak\"\n\n\nYeni paragraf")
        expect(json["body_format"]).to eq("plain")
        expect(json["body_html"]).to include("İlk satır<br>ikinci &lt;b&gt;kalın değil&lt;/b&gt; &amp;", "<br><br><br>Yeni paragraf")
        expect(JournalEntry.find(json["id"]).body.body.to_html)
          .to eq("<div>İlk satır<br>ikinci &lt;b&gt;kalın değil&lt;/b&gt; &amp; \"tırnak\"<br><br><br>Yeni paragraf</div>")
      end

      it "keeps script text as text" do
        post api_v1_journal_entries_path, params: { body_text: "<script>alert(1)</script>" }, headers: auth, as: :json

        expect(body["entry"]["body_text"]).to eq("<script>alert(1)</script>")
        expect(body["entry"]["body_html"]).not_to include("<script>")
        expect(body["entry"]["body_html"]).to include("&lt;script&gt;")
      end

      it "drops control characters PostgreSQL or HTML cannot hold" do
        post api_v1_journal_entries_path, params: { body_text: "a\u0000b\u0007c\td" }, headers: auth, as: :json

        expect(response).to have_http_status(:created)
        expect(body["entry"]["body_text"]).to eq("abc\td")
      end

      it "still stores body as HTML" do
        post api_v1_journal_entries_path, params: { body: "<div>Merhaba <em>dünya</em></div>" }, headers: auth, as: :json

        expect(body["entry"]).to include("body_text" => "Merhaba dünya", "body_formatting" => [ "italic" ])
      end

      it "422s with invalid_parameter when both body and body_text are sent, saving nothing" do
        post api_v1_journal_entries_path, params: { body: "<div>a</div>", body_text: "a" }, headers: auth, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(body).to include("code" => "invalid_parameter", "param" => "body")
        expect(user.journal_entries).to be_empty
      end

      it "422s with invalid_parameter for a body_text that is not a string" do
        [ 5, [ "a" ], { "a" => 1 } ].each do |value|
          post api_v1_journal_entries_path, params: { body_text: value }, headers: auth, as: :json
          expect(body).to include("code" => "invalid_parameter", "param" => "body_text"), "for #{value.inspect}"
        end
        expect(user.journal_entries).to be_empty
      end
    end

    describe "PATCH /api/v1/journal_entries/:id with body_text" do
      it "replaces a plain body" do
        entry = create(:journal_entry, user: user, body: "<div>Eski</div>")

        json = patch_entry(entry, { body_text: "Yeni\n\nmetin" })

        expect(response).to have_http_status(:ok)
        expect(json["entry"]).to include("body_text" => "Yeni\n\nmetin", "body_format" => "plain")
        expect(entry.reload.body.body.to_html).to eq("<div>Yeni<br><br>metin</div>")
      end

      it "turns the flat text an older app stored into real line breaks when saved again" do
        entry = create(:journal_entry, user: user, body: "Bir\n\nİki")

        patch_entry(entry, { body_text: "Bir\n\nİki" })

        expect(entry.reload.body.body.to_html).to eq("<div>Bir<br><br>İki</div>")
      end

      it "clears the body with null or \"\", and an empty body comes back as \"\" in every field" do
        [ { body_text: nil }, { body_text: "" }, { body: "" } ].each do |params|
          entry = create(:journal_entry, user: user, body: "<div>Silinecek</div>")
          expect(patch_entry(entry, params)["entry"]).to include("body_text" => "", "body_plain" => "", "body_html" => ""),
            "for #{params.inspect}"
        end
      end

      it "keeps a formatted body, formatting included, when its text comes back unchanged" do
        entry = create(:journal_entry, user: user, title: "Önce", body: web_html)
        get api_v1_journal_entry_path(entry), headers: auth
        text = body["entry"]["body_text"]

        json = patch_entry(entry, { title: "Sonra", mood: "great", body_text: "#{text.gsub("\n", "\r\n")}  \n" })

        expect(response).to have_http_status(:ok)
        expect(json["entry"]).to include("title" => "Sonra", "mood" => "great", "body_format" => "rich")
        expect(entry.reload.body.body.to_html).to eq(web_html)
      end

      it "422s with body_has_formatting when the text of a formatted body changes, saving nothing" do
        entry = create(:journal_entry, user: user, title: "Önce", body: web_html)

        json = patch_entry(entry, { title: "Sonra", body_text: "Sabah erken kalktım. Yeni cümle." })

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to include("code" => "body_has_formatting", "body_formatting" => [ "bold", "list" ])
        expect(json["errors"]).to have_key("body_text")
        expect(entry.reload.title).to eq("Önce")
        expect(entry.body.body.to_html).to eq(web_html)
      end

      it "replaces a formatted body with plain text once the client confirms with discard_formatting" do
        entry = create(:journal_entry, user: user, body: web_html)

        json = patch_entry(entry, { body_text: "Düz metin\n\nartık", discard_formatting: true })

        expect(response).to have_http_status(:ok)
        expect(json["entry"]).to include("body_text" => "Düz metin\n\nartık", "body_format" => "plain", "body_formatting" => [])
      end

      it "422s with invalid_parameter for a discard_formatting that is not a boolean, saving nothing" do
        entry = create(:journal_entry, user: user, title: "Önce", body: "<div>a</div>")

        json = patch_entry(entry, { title: "Sonra", body_text: "b", discard_formatting: "evet" })

        expect(json).to include("code" => "invalid_parameter", "param" => "discard_formatting")
        expect(entry.reload.title).to eq("Önce")
      end

      it "leaves the body alone when neither body nor body_text is sent" do
        entry = create(:journal_entry, user: user, body: web_html)

        patch_entry(entry, { title: "Başlık" })

        expect(entry.reload.body.body.to_html).to eq(web_html)
      end
    end

    describe "PATCH /api/v1/journal_entries/:id with body (older app versions)" do
      it "keeps the stored body when the text the app was shown comes back unchanged" do
        entry = create(:journal_entry, user: user, body: web_html)
        get api_v1_journal_entry_path(entry), headers: auth

        patch_entry(entry, { mood: "bad", body: body["entry"]["body_plain"].strip })

        expect(response).to have_http_status(:ok)
        expect(entry.reload.body.body.to_html).to eq(web_html)
        expect(entry.mood).to eq("bad")
      end

      it "stores a changed body as sent, as before" do
        entry = create(:journal_entry, user: user, body: web_html)

        patch_entry(entry, { body: "<div>Yeni</div>" })

        expect(entry.reload.body.body.to_html).to eq("<div>Yeni</div>")
      end
    end

    it "404s for another user's entry without touching it" do
      entry = create(:journal_entry, body: "<div>Onların</div>")

      json = patch_entry(entry, { body_text: "Benim" })

      expect(response).to have_http_status(:not_found)
      expect(json).to eq("error" => "not_found", "code" => "not_found")
      expect(entry.reload.body_text).to eq("Onların")
    end

    it "401s without a token" do
      entry = create(:journal_entry, user: user, body: "<div>a</div>")

      patch api_v1_journal_entry_path(entry), params: { body_text: "b" }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(body["code"]).to eq("unauthorized")
      expect(entry.reload.body_text).to eq("a")
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
