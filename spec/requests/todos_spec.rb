require 'rails_helper'

RSpec.describe "Todos", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /todos" do
    it "renders the open filter by default" do
      get todos_path
      expect(response).to have_http_status(:success)
    end

    it "scopes to the open filter (pending + in_progress) by default" do
      open_todo = create(:todo, user: user, status: "pending", title: "Open task")
      done_todo = create(:todo, user: user, status: "done", title: "Done task")

      get todos_path

      expect(response.body).to include("Open task")
      expect(response.body).not_to include("Done task")
    end

    it "filters by today" do
      create(:todo, user: user, status: "pending", title: "Due today task", due_at: Time.current)
      create(:todo, user: user, status: "pending", title: "Future task", due_at: 3.days.from_now)

      get todos_path, params: { filter: "today" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Due today task")
      expect(response.body).not_to include("Future task")
    end

    it "filters by this week" do
      create(:todo, user: user, status: "pending", title: "This week task", due_at: Date.current.beginning_of_week + 1.day)
      create(:todo, user: user, status: "pending", title: "Next week task", due_at: Date.current.end_of_week + 3.days)

      get todos_path, params: { filter: "week" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("This week task")
      expect(response.body).not_to include("Next week task")
    end

    it "filters by overdue" do
      create(:todo, user: user, status: "pending", title: "Overdue task", due_at: 2.days.ago)
      create(:todo, user: user, status: "pending", title: "Upcoming task", due_at: 2.days.from_now)

      get todos_path, params: { filter: "overdue" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Overdue task")
      expect(response.body).not_to include("Upcoming task")
    end

    it "filters by done" do
      create(:todo, user: user, status: "done", title: "Finished task")
      create(:todo, user: user, status: "pending", title: "Still pending task")

      get todos_path, params: { filter: "done" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Finished task")
      expect(response.body).not_to include("Still pending task")
    end

    it "filters by list_id" do
      list = create(:todo_list, user: user)
      create(:todo, user: user, status: "pending", title: "In the list", todo_list: list)
      create(:todo, user: user, status: "pending", title: "Not in the list")

      get todos_path, params: { list_id: list.id }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("In the list")
      expect(response.body).not_to include("Not in the list")
    end

    it "filters by priority" do
      create(:todo, user: user, status: "pending", priority: "high", title: "High prio task")
      create(:todo, user: user, status: "pending", priority: "low", title: "Low prio task")

      get todos_path, params: { priority: "high" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("High prio task")
      expect(response.body).not_to include("Low prio task")
    end

    it "renders successfully when the user has both active and archived lists" do
      # Exercises the @lists = current_user.todo_lists.active.ordered load in #index.
      create(:todo_list, user: user, name: "Active list")
      create(:todo_list, user: user, name: "Archived list", archived_at: Time.current)

      get todos_path

      expect(response).to have_http_status(:success)
    end

    it "does not include another user's todos" do
      other = create(:user)
      create(:todo, user: user, status: "pending", title: "My own task")
      create(:todo, user: other, status: "pending", title: "Their secret task")

      get todos_path

      expect(response.body).to include("My own task")
      expect(response.body).not_to include("Their secret task")
    end
  end

  describe "GET /todos/new" do
    it "renders the new form" do
      get new_todo_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /todos/:id" do
    it "renders the show page" do
      todo = create(:todo, user: user)

      get todo_path(todo)

      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /todos/:id/edit" do
    it "renders the edit form" do
      todo = create(:todo, user: user, title: "Editable task")
      create(:todo_list, user: user, name: "Pick me list")

      get edit_todo_path(todo)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Pick me list")
    end
  end

  describe "POST /todos" do
    it "creates a todo" do
      expect { post todos_path, params: { todo: { title: "Test", priority: "medium", status: "pending" } } }
        .to change(Todo, :count).by(1)
    end

    it "associates the created todo with the current user and redirects" do
      post todos_path, params: { todo: { title: "Owned", priority: "high", status: "pending" } }

      expect(response).to redirect_to(todos_path)
      created = Todo.last
      expect(created.user).to eq(user)
      expect(created.priority).to eq("high")
    end

    it "re-renders new with unprocessable_entity on invalid params" do
      expect {
        post todos_path, params: { todo: { title: "", priority: "medium", status: "pending" } }
      }.not_to change(Todo, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /todos/:id" do
    let(:todo) { create(:todo, user: user, status: "pending") }

    it "updates the todo and redirects" do
      patch todo_path(todo), params: { todo: { title: "Renamed" } }

      expect(response).to redirect_to(todos_path)
      expect(todo.reload.title).to eq("Renamed")
    end

    it "sets completed_at when status is updated to done" do
      patch todo_path(todo), params: { todo: { status: "done" } }

      todo.reload
      expect(todo.status).to eq("done")
      expect(todo.completed_at).to be_present
    end

    it "re-renders edit with unprocessable_entity on invalid params" do
      patch todo_path(todo), params: { todo: { title: "" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(todo.reload.title).not_to eq("")
    end
  end

  describe "DELETE /todos/:id" do
    it "destroys the todo and redirects" do
      todo = create(:todo, user: user)

      expect { delete todo_path(todo) }.to change(Todo, :count).by(-1)
      expect(response).to redirect_to(todos_path)
    end
  end

  describe "PATCH /todos/:id/toggle" do
    let(:todo) { create(:todo, user: user, status: "pending") }

    it "toggles status to done" do
      patch toggle_todo_path(todo)
      expect(todo.reload.status).to eq("done")
    end

    it "toggles back to pending" do
      todo.update(status: "done")
      patch toggle_todo_path(todo)
      expect(todo.reload.status).to eq("pending")
    end
  end

  describe "PATCH /todos/:id/reorder" do
    it "updates the position and returns ok" do
      todo = create(:todo, user: user)

      patch reorder_todo_path(todo), params: { position: 5 }

      expect(response).to have_http_status(:ok)
      expect(todo.reload.position).to eq(5)
    end
  end
end
