require "rails_helper"

# The web runs signed-in requests in the user's zone and language, like the
# API, so both agree on "today". Pinned to 22:30 UTC on 3 October, when it is
# already 01:30 on the 4th in Istanbul.
RSpec.describe "Web time zone and locale", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, timezone: "Istanbul", locale: "tr") }

  before do
    travel_to Time.utc(2026, 10, 3, 22, 30)
    sign_in user
  end

  # The series behind the sparkline of the dashboard stat card labelled `label`.
  def sparkline(label)
    card = Nokogiri::HTML(response.body).css(".card").find { |node| node.at_css("p")&.text&.strip == label }
    JSON.parse(card.at_css("[data-sparkline-data-value]")["data-sparkline-data-value"])
  end

  it "logs a habit toggled at 01:30 local time on the local date" do
    habit = create(:habit, user: user)

    patch toggle_today_habit_path(habit)

    expect(habit.habit_logs.sole.date).to eq(Date.new(2026, 10, 4))
  end

  # Local week: Monday 28 Sep 00:00 to Sunday 4 Oct 23:59:59 (+03:00).
  it "filters todos due this week by the local Monday to Sunday week" do
    create(:todo, user: user, title: "Week start task", due_at: Time.utc(2026, 9, 27, 22))
    create(:todo, user: user, title: "Week end task", due_at: Time.utc(2026, 10, 4, 19))
    create(:todo, user: user, title: "Next week task", due_at: Time.utc(2026, 10, 4, 21, 30))

    get todos_path(filter: "week")

    expect(response.body).to include("Week start task", "Week end task")
    expect(response.body).not_to include("Next week task")
  end

  it "buckets the dashboard's 7-day todo and event sparklines by local day" do
    todo = create(:todo, user: user, status: "done")
    todo.update_column(:completed_at, Time.utc(2026, 10, 3, 22)) # 01:00 on the 4th, local
    create(:event, user: user, start_at: Time.utc(2026, 10, 3, 21, 30)) # 00:30 on the 4th, local

    get root_path

    expect(sparkline(I18n.t("pages.home.open_todos", locale: :tr))).to eq([ 0, 0, 0, 0, 0, 0, 1 ])
    expect(sparkline(I18n.t("pages.home.todays_events", locale: :tr))).to eq([ 0, 0, 0, 0, 0, 0, 1 ])
  end

  it "shows a todo due early on the calendar grid's first day" do
    # October's grid starts on Monday 28 September; this is 01:00 local.
    create(:todo, user: user, title: "Grid start task", due_at: Time.utc(2026, 9, 27, 22))

    get calendar_path

    expect(response.body).to include("Grid start task")
  end

  it "counts a focus session early on the first local day of the insights window" do
    # The default 30-day window starts on 4 September; this is 01:00 local.
    create(:focus_session, user: user, started_at: Time.utc(2026, 9, 3, 22), completed_at: Time.utc(2026, 9, 3, 22, 25))

    get insights_path

    expect(response.body).to include(I18n.t("insights.focus_minutes", locale: :tr))
  end

  it "reads form datetimes as the user's wall clock" do
    event = create(:event, user: user, start_at: Time.utc(2026, 10, 4, 6))

    patch reschedule_event_path(event), params: { start_at: "2026-10-04T15:00" }, as: :json

    expect(event.reload.start_at).to eq(Time.utc(2026, 10, 4, 12))
  end

  it "renders in the user's language and leaves the thread's locale and zone as they were" do
    get root_path

    expect(response.body).to include('lang="tr"')
    expect(I18n.locale).to eq(I18n.default_locale)
    expect(Time.zone.name).to eq("UTC")
  end
end
