require 'rails_helper'

RSpec.describe "Todos", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /todos" do
    it "renders the open filter by default" do
      get todos_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /todos" do
    it "creates a todo" do
      expect { post todos_path, params: { todo: { title: "Test", priority: "medium", status: "pending" } } }
        .to change(Todo, :count).by(1)
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
end
