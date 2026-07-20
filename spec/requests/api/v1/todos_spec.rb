require "rails_helper"

RSpec.describe "Api::V1::Todos", type: :request do
  let(:user) { create(:user) }
  let(:auth) { { "Authorization" => "Bearer #{user.api_token}" } }

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
        expect(body["meta"]).to eq("open_count" => 3, "overdue_count" => 1)
      end

      it "serializes todo fields including its list" do
        pending_json = JSON.parse(response.body)["todos"].find { |t| t["title"] == "Pending" }
        expect(pending_json).to include(
          "status" => "pending", "priority" => "medium", "overdue" => false,
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

      patch toggle_api_v1_todo_path(todo), headers: auth

      expect(response).to have_http_status(:not_found)
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
end
