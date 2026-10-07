require "rails_helper"

# Every authenticated API request runs in the user's time zone and language
# (UserTimeZoneAndLocale). The clock is pinned to 22:30 UTC on 3 October,
# when Istanbul (+03:00) is already at 01:30 on the 4th, so anything still
# computed in UTC lands on the wrong day.
RSpec.describe "API time zone and locale", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, timezone: "Istanbul") }
  let(:local_today) { Date.new(2026, 10, 4) }

  def auth_for(someone) = { "Authorization" => "Bearer #{someone.api_token}" }
  def body = JSON.parse(response.body)

  before { travel_to Time.utc(2026, 10, 3, 22, 30) }

  describe "today" do
    it "logs a habit toggled at 01:30 local time on the local date" do
      habit = create(:habit, user: user, created_at: 1.week.ago)

      patch toggle_today_api_v1_habit_path(habit), headers: auth_for(user)

      expect(habit.habit_logs.sole.date).to eq(local_today)
      expect(body["habit"]["today"]["date"]).to eq("2026-10-04")
    end

    it "lets the explicit habit log endpoint accept the local today, not refuse it as the future" do
      habit = create(:habit, user: user, created_at: 1.week.ago)

      put log_api_v1_habit_path(habit, date: "2026-10-04"), params: { count: 1 }, headers: auth_for(user)

      expect(response).to have_http_status(:ok)
      expect(habit.habit_logs.sole.date).to eq(local_today)
    end

    it "computes /home for the local date and says which date that is" do
      account = create(:account, user: user)
      create(:transaction, user: user, account: account, amount_cents: 500, date: local_today)

      get api_v1_home_path, headers: auth_for(user)

      expect(body["today"]).to eq("2026-10-04")
      expect(body["spending_7d"].last).to eq("date" => "2026-10-04", "cents" => 500)
    end

    it "dates a quick-capture expense on the local date" do
      create(:account, user: user)

      post api_v1_quick_captures_path, params: { text: "-250 kahve" }, headers: auth_for(user)

      expect(user.transactions.sole.date).to eq(local_today)
    end

    it "filters todos due today by the local day" do
      create(:todo, user: user, title: "10:00 local", due_at: Time.utc(2026, 10, 4, 7))
      create(:todo, user: user, title: "23:00 local yesterday", due_at: Time.utc(2026, 10, 3, 20))

      get api_v1_todos_path(filter: "today"), headers: auth_for(user)

      expect(body["todos"].map { |todo| todo["title"] }).to eq([ "10:00 local" ])
    end

    # Local week: Monday 28 Sep 00:00 to Sunday 4 Oct 23:59:59 (+03:00).
    it "filters todos due this week by the local Monday to Sunday week" do
      create(:todo, user: user, title: "Mon 01:00 local", due_at: Time.utc(2026, 9, 27, 22))
      create(:todo, user: user, title: "Sun 22:00 local", due_at: Time.utc(2026, 10, 4, 19))
      create(:todo, user: user, title: "previous Sun 23:30 local", due_at: Time.utc(2026, 9, 27, 20, 30))
      create(:todo, user: user, title: "next Mon 00:30 local", due_at: Time.utc(2026, 10, 4, 21, 30))

      get api_v1_todos_path(filter: "week"), headers: auth_for(user)

      expect(body["todos"].map { |todo| todo["title"] }).to contain_exactly("Mon 01:00 local", "Sun 22:00 local")
    end

    it "lists events by the local day, including a recurring one when from == to" do
      create(:event, user: user, title: "Standup", recurring: true, recurrence_rule: "FREQ=DAILY",
                     start_at: Time.utc(2026, 9, 1, 6))
      create(:event, user: user, title: "Just after midnight", start_at: Time.utc(2026, 10, 3, 21, 30))

      get api_v1_events_path(from: "2026-10-04", to: "2026-10-04"), headers: auth_for(user)

      expect(body["events"].map { |event| event["title"] }).to eq([ "Standup", "Just after midnight" ])
      expect(body["events"].map { |event| event["occurrences"] }).to all(eq([ "2026-10-04" ]))
    end

    it "gives two users in different zones their own today at the same instant" do
      hawaii = create(:user, timezone: "Hawaii")

      get api_v1_habits_path, headers: auth_for(user)
      istanbul_chain_end = body["meta"]["perfect_day"]["chain"].last["date"]
      get api_v1_habits_path, headers: auth_for(hawaii)

      expect(istanbul_chain_end).to eq("2026-10-04")
      expect(body["meta"]["perfect_day"]["chain"].last["date"]).to eq("2026-10-03")
    end
  end

  describe "datetimes" do
    it "renders them with the user's offset and reads naive ones as the user's wall clock" do
      post api_v1_todos_path, params: { title: "Call", due_at: "2026-10-05T09:00" }, headers: auth_for(user)

      expect(user.todos.sole.due_at).to eq(Time.utc(2026, 10, 5, 6))
      expect(body["todo"]["due_at"]).to eq("2026-10-05T09:00:00.000+03:00")
    end

    it "keeps explicit offsets as sent" do
      post api_v1_todos_path, params: { title: "Call", due_at: "2026-10-05T09:00:00Z" }, headers: auth_for(user)

      expect(user.todos.sole.due_at).to eq(Time.utc(2026, 10, 5, 9))
      expect(body["todo"]["due_at"]).to eq("2026-10-05T12:00:00.000+03:00")
    end

    it "describes the zone in the user payload" do
      get api_v1_me_path, headers: auth_for(user)

      expect(body["user"]).to include("timezone" => "Istanbul", "timezone_iana" => "Europe/Istanbul", "utc_offset" => "+03:00")
    end
  end

  describe "calendar dates in monthly totals" do
    it "keeps a transaction on the 1st in its own month for zones west of UTC" do
      travel_to Time.utc(2026, 7, 15, 12)
      pacific = create(:user, timezone: "Pacific Time (US & Canada)")
      create(:transaction, :income, user: pacific, amount_cents: 10_000, date: Date.new(2026, 7, 1))

      get api_v1_finance_dashboard_path, headers: auth_for(pacific)

      series = body["six_month_series"]
      expect(series["labels"].last).to eq("2026-07")
      expect(series["income_cents"].last(2)).to eq([ 0, 10_000 ])
    end
  end

  describe "locale" do
    let(:turkish) { create(:user, locale: "tr") }
    let(:english) { create(:user, locale: "en") }

    it "words validation errors in each user's language without leaking it to the next request" do
      post api_v1_habits_path, params: { name: "" }, headers: auth_for(turkish)
      expect(body["errors"]["name"]).to eq([ "Ad boş bırakılamaz" ])

      post api_v1_habits_path, params: { name: "" }, headers: auth_for(english)
      expect(body["errors"]["name"]).to eq([ "Name can't be blank" ])
      expect(body["details"]["name"]).to eq([ { "error" => "blank" } ])
    end

    it "restores the thread's locale and zone after the request" do
      post api_v1_habits_path, params: { name: "" }, headers: auth_for(create(:user, locale: "tr", timezone: "Tokyo"))

      expect(I18n.locale).to eq(I18n.default_locale)
      expect(Time.zone.name).to eq("UTC")
    end

    it "words errors rendered by rescue_from handlers in the user's language too" do
      habit = create(:habit, user: turkish)
      habit.update_column(:name, "")

      patch archive_api_v1_habit_path(habit), headers: auth_for(turkish)

      expect(response).to have_http_status(:unprocessable_content)
      expect(body).to include("code" => "validation_failed", "errors" => { "name" => [ "Ad boş bırakılamaz" ] })
    end

    it "falls back to the app defaults for a zone or locale the app does not know" do
      user.update_columns(timezone: "Mars/Olympus", locale: "de")

      get api_v1_home_path, headers: auth_for(user)
      expect(body["today"]).to eq("2026-10-03")

      post api_v1_habits_path, params: { name: "" }, headers: auth_for(user)
      expect(body["errors"]["name"]).to eq([ "Name can't be blank" ])
    end
  end
end
