require 'rails_helper'

RSpec.describe "TodoLists", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /todo_lists" do
    it "renders" do
      create(:todo_list, user: user)
      get todo_lists_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /todo_lists/new" do
    it "renders the new form" do
      get new_todo_list_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /todo_lists" do
    it "creates a list with valid params" do
      expect {
        post todo_lists_path, params: { todo_list: { name: "Work", color: "#B8860B" } }
      }.to change(user.todo_lists, :count).by(1)
      expect(response).to redirect_to(todo_lists_path)
    end

    it "re-renders new with invalid params" do
      post todo_lists_path, params: { todo_list: { name: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /todo_lists/:id" do
    let(:list) { create(:todo_list, user: user, name: "Old") }

    it "updates the list" do
      patch todo_list_path(list), params: { todo_list: { name: "New" } }
      expect(list.reload.name).to eq("New")
    end
  end

  describe "DELETE /todo_lists/:id" do
    it "destroys the list" do
      list = create(:todo_list, user: user)
      expect { delete todo_list_path(list) }.to change(user.todo_lists, :count).by(-1)
    end
  end
end
