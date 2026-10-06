require "rails_helper"

RSpec.describe "Api::V1::Todos", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:auth) { { "Authorization" => "Bearer #{user.api_token}" } }

  def body = JSON.parse(response.body)

  it "401s without a token" do
    get api_v1_todos_path

    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)["error"]).to eq("unauthorized")
  end

  describe "GET /api/v1/todos" do
    context "without a filter" do
      let!(:list) { create(:todo_list, user: user, name: "Errands") }

      before do
        create(:todo, user: user, title: "Pending", todo_list: list)
        create(:todo, user: user, title: "In progress", status: "in_progress")
        create(:todo, user: user, title: "Overdue", due_at: 2.days.ago)
        create(:todo, user: user, title: "Done", status: "done")
        create(:todo, title: "Someone else's")
        get api_v1_todos_path, headers: auth
      end

      it "returns only the user's open todos with meta counts" do
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["todos"].map { |t| t["title"] }).to contain_exactly("Pending", "In progress", "Overdue")
        expect(body["meta"]).to include("open_count" => 3, "overdue_count" => 1, "total_count" => 3)
        expect(body["meta"]).not_to have_key("page")
      end

      it "serializes todo fields including its list" do
        pending_json = JSON.parse(response.body)["todos"].find { |t| t["title"] == "Pending" }
        expect(pending_json).to include(
          "status" => "pending", "priority" => "medium", "completed_at" => nil, "overdue" => false,
          "position" => 0, "subtask_count" => 0
        )
        expect(pending_json["todo_list"]).to include("id" => list.id, "name" => "Errands", "color" => "#B8860B")
      end
    end

    it "filters to todos due today" do
      create(:todo, user: user, title: "Today", due_at: Date.current.noon)
      create(:todo, user: user, title: "Tomorrow", due_at: Date.tomorrow.noon)
      create(:todo, user: user, title: "Done today", status: "done", due_at: Date.current.noon)

      get api_v1_todos_path(filter: "today"), headers: auth

      expect(JSON.parse(response.body)["todos"].map { |t| t["title"] }).to eq([ "Today" ])
    end

    it "filters to overdue todos and flags them" do
      create(:todo, user: user, title: "Late", due_at: 3.days.ago)
      create(:todo, user: user, title: "On time", due_at: 3.days.from_now)

      get api_v1_todos_path(filter: "overdue"), headers: auth

      body = JSON.parse(response.body)
      expect(body["todos"].map { |t| t["title"] }).to eq([ "Late" ])
      expect(body["todos"].first["overdue"]).to be(true)
      expect(body["meta"]["overdue_count"]).to eq(1)
    end

    it "filters to done todos" do
      create(:todo, user: user, title: "Finished", status: "done")
      create(:todo, user: user, title: "Open")

      get api_v1_todos_path(filter: "done"), headers: auth

      expect(JSON.parse(response.body)["todos"].map { |t| t["title"] }).to eq([ "Finished" ])
    end

    it "filters by list_id and priority" do
      list = create(:todo_list, user: user)
      create(:todo, user: user, title: "Listed urgent", todo_list: list, priority: "urgent")
      create(:todo, user: user, title: "Listed low", todo_list: list, priority: "low")
      create(:todo, user: user, title: "Unlisted")

      get api_v1_todos_path(list_id: list.id, priority: "urgent"), headers: auth

      expect(JSON.parse(response.body)["todos"].map { |t| t["title"] }).to eq([ "Listed urgent" ])
    end
  end

  describe "PATCH /api/v1/todos/:id/toggle" do
    it "flips a pending todo to done" do
      todo = create(:todo, user: user)

      patch toggle_api_v1_todo_path(todo), headers: auth

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include("id" => todo.id, "status" => "done")
      expect(todo.reload.completed_at).to be_present
    end

    it "flips a done todo back to pending" do
      todo = create(:todo, user: user, status: "done")

      patch toggle_api_v1_todo_path(todo), headers: auth

      expect(JSON.parse(response.body)).to include("id" => todo.id, "status" => "pending", "completed_at" => nil)
      expect(todo.reload.completed_at).to be_nil
    end

    it "404s for another user's todo" do
      todo = create(:todo)

      patch toggle_api_v1_todo_path(todo), params: { done: true }, headers: auth

      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)).to eq("error" => "not_found", "code" => "not_found")
      expect(todo.reload.status).to eq("pending")
    end

    context "with an explicit done state" do
      def toggle(todo, done)
        patch toggle_api_v1_todo_path(todo), params: { done: done }, headers: auth, as: :json
        JSON.parse(response.body)
      end

      it "completes a pending todo and returns the full todo too" do
        todo = create(:todo, user: user)

        body = toggle(todo, true)

        expect(response).to have_http_status(:ok)
        expect(body).to include("id" => todo.id, "status" => "done")
        expect(body["completed_at"]).to be_present
        expect(body["todo"]).to include("id" => todo.id, "title" => todo.title, "status" => "done")
      end

      # Older clients read the nested todo whenever it is there, so it must
      # carry every top-level key, completed_at included.
      it "repeats the top-level keys inside the nested todo" do
        todo = create(:todo, user: user)

        body = toggle(todo, true)

        expect(body["completed_at"]).to be_present
        expect(body["todo"].slice("id", "status", "completed_at")).to eq(body.slice("id", "status", "completed_at"))
        expect(toggle(todo, false)["todo"]).to include("status" => "pending", "completed_at" => nil)
      end

      it "is idempotent: done=true twice keeps it done with the first completion time" do
        todo = create(:todo, user: user)
        toggle(todo, true)
        completed_at = todo.reload.completed_at

        body = toggle(todo, true)

        expect(body["status"]).to eq("done")
        expect(todo.reload.completed_at).to eq(completed_at)
      end

      it "reopens a done todo with done=false, and repeating it keeps it pending" do
        todo = create(:todo, user: user, status: "done")

        toggle(todo, false)
        body = toggle(todo, false)

        expect(body).to include("status" => "pending", "completed_at" => nil)
        expect(todo.reload.status).to eq("pending")
      end

      it "leaves in_progress and cancelled todos alone on done=false" do
        in_progress = create(:todo, user: user, status: "in_progress")
        cancelled = create(:todo, user: user, status: "cancelled")

        expect(toggle(in_progress, false)["status"]).to eq("in_progress")
        expect(toggle(cancelled, false)["status"]).to eq("cancelled")
      end

      it "completes an in_progress todo on done=true" do
        todo = create(:todo, user: user, status: "in_progress")

        expect(toggle(todo, true)["status"]).to eq("done")
      end

      it "accepts form-encoded 1/0 and true/false strings" do
        todo = create(:todo, user: user)

        patch toggle_api_v1_todo_path(todo), params: { done: "1" }, headers: auth
        expect(todo.reload.status).to eq("done")
        patch toggle_api_v1_todo_path(todo), params: { done: "false" }, headers: auth
        expect(todo.reload.status).to eq("pending")
      end

      it "422s with code invalid_parameter for a value that is not a boolean" do
        todo = create(:todo, user: user)

        body = toggle(todo, "maybe")

        expect(response).to have_http_status(:unprocessable_content)
        expect(body).to include("code" => "invalid_parameter", "param" => "done")
        expect(todo.reload.status).to eq("pending")
      end
    end

    it "422s with the record's errors when the todo cannot be saved" do
      todo = create(:todo, user: user)
      todo.update_column(:title, "x" * 201)

      patch toggle_api_v1_todo_path(todo), params: { done: true }, headers: auth

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)).to include("code" => "validation_failed")
      expect(todo.reload.status).to eq("pending")
    end
  end

  describe "POST /api/v1/todos" do
    it "creates a todo with list and goal resolved through the current user" do
      list = create(:todo_list, user: user)
      goal = create(:goal, user: user)

      expect {
        post api_v1_todos_path,
             params: { title: "Ship it", body: "Details", priority: "high",
                       due_at: 2.days.from_now.iso8601, todo_list_id: list.id, goal_id: goal.id },
             headers: auth
      }.to change(user.todos, :count).by(1)

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)["todo"]
      expect(json).to include("title" => "Ship it", "priority" => "high", "status" => "pending")
      expect(json["todo_list"]["id"]).to eq(list.id)
      expect(user.todos.last.goal_id).to eq(goal.id)
    end

    it "404s when the todo_list belongs to another user" do
      other_list = create(:todo_list)

      expect {
        post api_v1_todos_path, params: { title: "Sneaky", todo_list_id: other_list.id }, headers: auth
      }.not_to change(Todo, :count)

      expect(response).to have_http_status(:not_found)
    end

    it "404s when the goal belongs to another user" do
      other_goal = create(:goal)

      post api_v1_todos_path, params: { title: "Sneaky", goal_id: other_goal.id }, headers: auth

      expect(response).to have_http_status(:not_found)
    end

    it "422s without a title" do
      post api_v1_todos_path, params: { body: "No title" }, headers: auth

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["errors"]).to have_key("title")
    end
  end

  describe "PATCH /api/v1/todos/:id" do
    it "updates the todo" do
      todo = create(:todo, user: user, priority: "low")

      patch api_v1_todo_path(todo), params: { priority: "urgent", title: "Renamed" }, headers: auth

      expect(response).to have_http_status(:ok)
      expect(todo.reload).to have_attributes(priority: "urgent", title: "Renamed")
    end

    it "404s for another user's todo" do
      todo = create(:todo, title: "Untouchable")

      patch api_v1_todo_path(todo), params: { title: "Hacked" }, headers: auth

      expect(response).to have_http_status(:not_found)
      expect(todo.reload.title).to eq("Untouchable")
    end
  end

  describe "GET /api/v1/todos filters for a full todo screen" do
    # Wednesday 7 October 2026, 12:00 (the user's zone is UTC). The week runs
    # Monday 5 to Sunday 11.
    before do
      travel_to Time.utc(2026, 10, 7, 12)
      create(:todo, user: user, title: "Yesterday", due_at: Time.utc(2026, 10, 6, 9))
      create(:todo, user: user, title: "Today 09:00", due_at: Time.utc(2026, 10, 7, 9))
      create(:todo, user: user, title: "Today, no time", due_at: Todo.end_of_due_day(Date.new(2026, 10, 7)))
      create(:todo, user: user, title: "Tomorrow", due_at: Time.utc(2026, 10, 8, 10))
      create(:todo, user: user, title: "In 7 days", due_at: Time.utc(2026, 10, 14, 18))
      create(:todo, user: user, title: "In 8 days", due_at: Time.utc(2026, 10, 15, 9))
      create(:todo, user: user, title: "Undated")
      create(:todo, user: user, title: "Done", status: "done")
      create(:todo, user: user, title: "Cancelled", status: "cancelled", due_at: Time.utc(2026, 10, 8, 9))
      create(:todo, title: "Someone else's", due_at: Time.utc(2026, 10, 8, 9))
    end

    def titles(**query)
      get api_v1_todos_path(query), headers: auth
      expect(response).to have_http_status(:ok)
      body["todos"].map { |todo| todo["title"] }
    end

    it "keeps the existing filters as they were" do
      expect(titles(filter: "today")).to contain_exactly("Today 09:00", "Today, no time")
      expect(titles(filter: "week")).to contain_exactly("Yesterday", "Today 09:00", "Today, no time", "Tomorrow")
      expect(titles(filter: "overdue")).to contain_exactly("Yesterday", "Today 09:00")
      expect(titles(filter: "done")).to eq([ "Done" ])
      expect(titles).to contain_exactly("Yesterday", "Today 09:00", "Today, no time", "Tomorrow", "In 7 days", "In 8 days", "Undated")
    end

    it "lists the open todos due in the 7 days after today with upcoming" do
      expect(titles(filter: "upcoming")).to contain_exactly("Tomorrow", "In 7 days")
    end

    it "lists the open todos without a due date with undated" do
      expect(titles(filter: "undated")).to eq([ "Undated" ])
    end

    it "lists cancelled todos, every todo with all, and accepts open by name" do
      expect(titles(filter: "cancelled")).to eq([ "Cancelled" ])
      expect(titles(filter: "all").size).to eq(9)
      expect(titles(filter: "open").size).to eq(7)
    end

    it "does not count a date-only todo as overdue during its day" do
      get api_v1_todos_path(filter: "today"), headers: auth

      date_only = body["todos"].find { |todo| todo["title"] == "Today, no time" }
      expect(date_only).to include("overdue" => false, "due_date" => "2026-10-07", "due_time" => nil)
    end

    it "counts every filter in meta.counts, and total_count is the requested filter's" do
      get api_v1_todos_path(filter: "upcoming"), headers: auth

      expect(body["meta"]["counts"]).to eq(
        "open" => 7, "today" => 2, "week" => 4, "upcoming" => 2, "overdue" => 2,
        "undated" => 1, "done" => 1, "cancelled" => 1, "all" => 9
      )
      expect(body["meta"]).to include("total_count" => 2, "open_count" => 7, "overdue_count" => 2)
    end

    it "422s for an unknown filter, sort or priority" do
      %i[filter sort priority].each do |param|
        get api_v1_todos_path(param => "bogus"), headers: auth

        expect(response).to have_http_status(:unprocessable_content)
        expect(body).to include("code" => "invalid_parameter", "param" => param.to_s)
      end
    end

    it "sorts by due date, undated last, with sort=due" do
      expect(titles(sort: "due")).to eq([ "Yesterday", "Today 09:00", "Today, no time", "Tomorrow", "In 7 days", "In 8 days", "Undated" ])
    end

    it "sorts the most recently completed first with sort=completed" do
      Todo.find_by!(title: "Done").update_columns(completed_at: 3.days.ago)
      create(:todo, user: user, title: "Done later", status: "done").update_columns(completed_at: 1.hour.ago)

      expect(titles(filter: "done", sort: "completed")).to eq([ "Done later", "Done" ])
    end

    it "sorts the newest first with sort=created" do
      create(:todo, user: user, title: "Newest")

      expect(titles(sort: "created").first).to eq("Newest")
    end

    it "pages the list when page or per_page is given" do
      get api_v1_todos_path(sort: "due", page: 2, per_page: 2), headers: auth

      expect(body["todos"].map { |todo| todo["title"] }).to eq([ "Today, no time", "Tomorrow" ])
      expect(body["meta"]).to include("page" => 2, "per_page" => 2, "total_count" => 7)

      get api_v1_todos_path(per_page: 5), headers: auth
      expect(body["todos"].size).to eq(5)
      expect(body["meta"]).to include("page" => 1, "per_page" => 5)
    end

    it "422s for a page or per_page out of range or not a number" do
      [ { page: 0 }, { page: "abc" }, { per_page: 0 }, { per_page: 201 } ].each do |query|
        get api_v1_todos_path(query), headers: auth

        expect(response).to have_http_status(:unprocessable_content)
        expect(body).to include("code" => "invalid_parameter", "param" => query.keys.first.to_s)
      end
    end
  end

  describe "GET /api/v1/todos list_id" do
    let!(:list) { create(:todo_list, user: user) }

    before do
      create(:todo, user: user, title: "Listed", todo_list: list, priority: "high")
      create(:todo, user: user, title: "Listed low", todo_list: list, priority: "low")
      create(:todo, user: user, title: "Unlisted", due_at: 1.day.ago)
    end

    it "lists the todos in no list with list_id=none" do
      get api_v1_todos_path(list_id: "none"), headers: auth

      expect(body["todos"].map { |todo| todo["title"] }).to eq([ "Unlisted" ])
    end

    it "narrows meta.counts by list and priority but keeps open_count and overdue_count for all todos" do
      get api_v1_todos_path(list_id: list.id, priority: "high"), headers: auth

      expect(body["todos"].map { |todo| todo["title"] }).to eq([ "Listed" ])
      expect(body["meta"]["counts"]).to include("open" => 1, "overdue" => 0, "all" => 1)
      expect(body["meta"]).to include("open_count" => 3, "overdue_count" => 1, "total_count" => 1)
    end

    it "accepts an archived list" do
      list.update!(archived_at: Time.current)

      get api_v1_todos_path(list_id: list.id), headers: auth

      expect(body["todos"].size).to eq(2)
    end

    it "404s for another user's list and 422s for an id that is not a number" do
      get api_v1_todos_path(list_id: create(:todo_list).id), headers: auth
      expect(response).to have_http_status(:not_found)
      expect(body).to eq("error" => "not_found", "code" => "not_found")

      get api_v1_todos_path(list_id: "abc"), headers: auth
      expect(response).to have_http_status(:unprocessable_content)
      expect(body).to include("code" => "invalid_parameter", "param" => "list_id")
    end

    it "ignores an empty list_id, as before" do
      get api_v1_todos_path(list_id: ""), headers: auth

      expect(body["todos"].size).to eq(3)
    end
  end

  describe "GET /api/v1/todos/:id" do
    it "returns the todo with its goal and due date parts" do
      goal = create(:goal, user: user)
      todo = create(:todo, user: user, goal: goal, body: "Notes", due_at: Time.utc(2026, 10, 5, 9, 30))

      get api_v1_todo_path(todo), headers: auth

      expect(response).to have_http_status(:ok)
      expect(body["todo"]).to include(
        "id" => todo.id, "body" => "Notes", "goal_id" => goal.id,
        "due_at" => "2026-10-05T09:30:00.000Z", "due_date" => "2026-10-05", "due_time" => "09:30"
      )
    end

    it "404s for another user's todo" do
      get api_v1_todo_path(create(:todo)), headers: auth

      expect(response).to have_http_status(:not_found)
      expect(body["code"]).to eq("not_found")
    end

    it "401s without a token" do
      get api_v1_todo_path(create(:todo, user: user))

      expect(response).to have_http_status(:unauthorized)
      expect(body["code"]).to eq("unauthorized")
    end
  end

  describe "due dates" do
    let(:user) { create(:user, timezone: "Istanbul") }

    # 00:30 on Monday 5 October in Istanbul.
    before { travel_to Time.utc(2026, 10, 4, 21, 30) }

    def create_todo(**params)
      post api_v1_todos_path, params: { title: "Faturayı öde", **params }, headers: auth, as: :json
    end

    it "stores a date without a time as the end of that local day" do
      create_todo(due_date: "2026-10-05")

      expect(response).to have_http_status(:created)
      expect(body["todo"]).to include(
        "due_at" => "2026-10-05T23:59:59.000+03:00", "due_date" => "2026-10-05", "due_time" => nil, "overdue" => false
      )
      expect(user.todos.sole.due_at).to eq(Time.utc(2026, 10, 5, 20, 59, 59))
    end

    it "keeps a date-only todo due today, not overdue, until its day is over" do
      create_todo(due_date: "2026-10-05")

      travel_to Time.utc(2026, 10, 5, 20, 0) # 23:00 local
      get api_v1_todos_path(filter: "today"), headers: auth
      expect(body["todos"].sole).to include("overdue" => false)
      expect(body["meta"]["overdue_count"]).to eq(0)

      travel_to Time.utc(2026, 10, 5, 21, 0, 1) # 00:00:01 the next day
      get api_v1_todos_path(filter: "overdue"), headers: auth
      expect(body["todos"].sole).to include("overdue" => true)
    end

    it "stores a date and a time as that local time" do
      create_todo(due_date: "2026-10-05", due_time: "09:30")

      expect(body["todo"]).to include("due_at" => "2026-10-05T09:30:00.000+03:00", "due_time" => "09:30")
    end

    it "reads a bare date in due_at as a date-only due" do
      create_todo(due_at: "2026-10-06")

      expect(body["todo"]).to include("due_at" => "2026-10-06T23:59:59.000+03:00", "due_time" => nil)
    end

    it "still takes a datetime in due_at as that instant" do
      create_todo(due_at: "2026-10-06T08:15:00Z")

      expect(body["todo"]).to include("due_at" => "2026-10-06T11:15:00.000+03:00", "due_time" => "11:15")
    end

    [
      [ { due_at: "2026-10-06T09:00", due_date: "2026-10-06" }, "invalid_parameter", "due_at" ],
      [ { due_time: "09:00" }, "invalid_parameter", "due_time" ],
      [ { due_date: "2026-10-06", due_time: "9:00" }, "invalid_parameter", "due_time" ],
      [ { due_date: "2026-10-06", due_time: "24:00" }, "invalid_parameter", "due_time" ],
      [ { due_date: "2026-10-06", due_time: 930 }, "invalid_parameter", "due_time" ],
      [ { due_date: "2026-02-30" }, "invalid_date", "due_date" ],
      [ { due_date: "06.10.2026" }, "invalid_date", "due_date" ],
      [ { due_at: "garbage" }, "invalid_datetime", "due_at" ],
      [ { due_at: "2026-02-30T10:00" }, "invalid_datetime", "due_at" ],
      [ { due_at: "2026-10-06T10:00+25:00" }, "invalid_datetime", "due_at" ],
      [ { due_at: "2026-10-06 10:00" }, "invalid_datetime", "due_at" ]
    ].each do |params, code, param|
      it "422s with #{code} for #{params.inspect} and creates nothing" do
        expect { create_todo(**params) }.not_to change(Todo, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(body).to include("code" => code, "param" => param)
        expect(body["errors"]).to have_key(param)
      end
    end

    describe "PATCH" do
      let(:todo) { create(:todo, user: user, due_at: Time.utc(2026, 10, 6, 11, 15)) } # 14:15 local

      def patch_todo(target = todo, **params)
        patch api_v1_todo_path(target), params: params, headers: auth, as: :json
      end

      it "moves the date and keeps the time of day when only due_date is sent" do
        patch_todo(due_date: "2026-10-09")

        expect(body["todo"]).to include("due_at" => "2026-10-09T14:15:00.000+03:00", "due_time" => "14:15")
      end

      it "keeps a date-only due date-only when only due_date is sent" do
        todo.update!(due_at: Time.use_zone(user.timezone) { Todo.end_of_due_day(Date.new(2026, 10, 6)) })

        patch_todo(due_date: "2026-10-09")

        expect(body["todo"]).to include("due_at" => "2026-10-09T23:59:59.000+03:00", "due_date" => "2026-10-09", "due_time" => nil)
      end

      it "changes the time and keeps the date when only due_time is sent, and null makes it date-only" do
        patch_todo(due_time: "08:00")
        expect(body["todo"]).to include("due_at" => "2026-10-06T08:00:00.000+03:00")

        patch_todo(due_time: nil)
        expect(body["todo"]).to include("due_at" => "2026-10-06T23:59:59.000+03:00", "due_time" => nil)
      end

      it "clears the due date with due_date null" do
        patch_todo(due_date: nil)

        expect(body["todo"]).to include("due_at" => nil, "due_date" => nil, "due_time" => nil)
      end

      it "422s for a time on a todo without a due date, leaving it unchanged" do
        undated = create(:todo, user: user)

        patch_todo(undated, due_time: "09:00")

        expect(response).to have_http_status(:unprocessable_content)
        expect(body).to include("code" => "invalid_parameter", "param" => "due_time")
        expect(undated.reload.due_at).to be_nil
      end
    end
  end

  describe "POST /api/v1/todos (more fields)" do
    it "takes a status, a position and notes" do
      post api_v1_todos_path, params: { title: "Started", status: "in_progress", position: 3, body: "Notes" },
                              headers: auth, as: :json

      expect(response).to have_http_status(:created)
      expect(body["todo"]).to include("status" => "in_progress", "position" => 3, "body" => "Notes", "goal_id" => nil)
    end

    it "sets completed_at when created done" do
      post api_v1_todos_path, params: { title: "Already done", status: "done" }, headers: auth, as: :json

      expect(body["todo"]["completed_at"]).to be_present
    end

    it "422s with validation details for an unknown status or priority" do
      post api_v1_todos_path, params: { title: "X", status: "archived", priority: "asap" }, headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(body["code"]).to eq("validation_failed")
      expect(body["details"]).to include(
        "status" => [ { "error" => "inclusion", "value" => "archived" } ],
        "priority" => [ { "error" => "inclusion", "value" => "asap" } ]
      )
    end

    it "422s for a title over 200 characters" do
      post api_v1_todos_path, params: { title: "x" * 201 }, headers: auth, as: :json

      expect(body["details"]["title"]).to eq([ { "error" => "too_long", "count" => 200 } ])
    end

    it "422s for a position or list id that is not a whole number" do
      [ { position: "first" }, { position: nil }, { todo_list_id: "abc" }, { goal_id: 1.5 } ].each do |params|
        expect {
          post api_v1_todos_path, params: { title: "X", **params }, headers: auth, as: :json
        }.not_to change(Todo, :count)

        expect(body).to include("code" => "invalid_parameter", "param" => params.keys.first.to_s)
      end
    end

    it "422s with value_out_of_range for a position beyond a 4-byte integer" do
      post api_v1_todos_path, params: { title: "X", position: 2**31 }, headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(body["code"]).to eq("value_out_of_range")
    end

    it "401s without a token" do
      expect { post api_v1_todos_path, params: { title: "X" } }.not_to change(Todo, :count)

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/todos/:id (only the keys sent)" do
    let(:list) { create(:todo_list, user: user) }
    let(:goal) { create(:goal, user: user) }
    let(:todo) do
      create(:todo, user: user, title: "Pay", body: "Notes", todo_list: list, goal: goal,
                    due_at: Time.utc(2026, 10, 6, 9), priority: "low")
    end

    it "leaves the fields that were not sent alone" do
      patch api_v1_todo_path(todo), params: { priority: "urgent" }, headers: auth, as: :json

      expect(response).to have_http_status(:ok)
      expect(todo.reload).to have_attributes(
        priority: "urgent", title: "Pay", body: "Notes", todo_list_id: list.id, goal_id: goal.id,
        due_at: Time.utc(2026, 10, 6, 9)
      )
    end

    it "clears the notes, list, goal and due date sent as null" do
      patch api_v1_todo_path(todo), params: { body: nil, todo_list_id: nil, goal_id: nil, due_at: nil }, headers: auth, as: :json

      expect(todo.reload).to have_attributes(body: nil, todo_list_id: nil, goal_id: nil, due_at: nil)
      expect(body["todo"]).to include("todo_list" => nil, "goal_id" => nil)
    end

    it "clears the list with an empty todo_list_id from a form, as before" do
      patch api_v1_todo_path(todo), params: { todo_list_id: "" }, headers: auth

      expect(response).to have_http_status(:ok)
      expect(todo.reload.todo_list_id).to be_nil
    end

    it "sets the status, keeping completed_at in step" do
      patch api_v1_todo_path(todo), params: { status: "done" }, headers: auth, as: :json
      expect(todo.reload.completed_at).to be_present

      patch api_v1_todo_path(todo), params: { status: "cancelled" }, headers: auth, as: :json
      expect(todo.reload).to have_attributes(status: "cancelled", completed_at: nil)
    end

    it "404s without changing anything when moving the todo to another user's list or goal" do
      patch api_v1_todo_path(todo), params: { title: "Moved", todo_list_id: create(:todo_list).id }, headers: auth, as: :json
      expect(response).to have_http_status(:not_found)

      patch api_v1_todo_path(todo), params: { title: "Moved", goal_id: create(:goal).id }, headers: auth, as: :json
      expect(response).to have_http_status(:not_found)
      expect(todo.reload).to have_attributes(title: "Pay", todo_list_id: list.id, goal_id: goal.id)
    end

    it "422s for a blank title" do
      patch api_v1_todo_path(todo), params: { title: "" }, headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(body["details"]["title"]).to eq([ { "error" => "blank" } ])
      expect(todo.reload.title).to eq("Pay")
    end
  end

  describe "DELETE /api/v1/todos/:id" do
    it "deletes the todo" do
      todo = create(:todo, user: user)

      expect { delete api_v1_todo_path(todo), headers: auth }.to change(Todo, :count).by(-1)

      expect(response).to have_http_status(:no_content)
      expect(response.body).to be_empty
    end

    it "keeps its subtasks without a parent and its focus sessions unlinked" do
      todo = create(:todo, user: user)
      subtask = create(:todo, user: user, parent: todo)
      session = create(:focus_session, user: user, todo: todo)

      delete api_v1_todo_path(todo), headers: auth

      expect(response).to have_http_status(:no_content)
      expect(subtask.reload.parent_id).to be_nil
      expect(session.reload.todo_id).to be_nil
    end

    it "404s for another user's todo and deletes nothing" do
      todo = create(:todo)

      expect { delete api_v1_todo_path(todo), headers: auth }.not_to change(Todo, :count)

      expect(response).to have_http_status(:not_found)
      expect(body["code"]).to eq("not_found")
    end

    it "401s without a token" do
      todo = create(:todo, user: user)

      expect { delete api_v1_todo_path(todo) }.not_to change(Todo, :count)

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
