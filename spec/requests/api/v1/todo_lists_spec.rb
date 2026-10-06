require "rails_helper"

RSpec.describe "Api::V1::TodoLists", type: :request do
  let(:user) { create(:user) }
  let(:auth) { { "Authorization" => "Bearer #{user.api_token}" } }

  def body = JSON.parse(response.body)

  it "401s without a token" do
    get api_v1_todo_lists_path

    expect(response).to have_http_status(:unauthorized)
    expect(body).to eq("error" => "unauthorized", "code" => "unauthorized")
  end

  describe "GET /api/v1/todo_lists" do
    let!(:home) { create(:todo_list, user: user, name: "Ev", position: 1, color: "#6B8E5A") }
    let!(:work) { create(:todo_list, user: user, name: "İş", position: 0) }
    let!(:old) { create(:todo_list, user: user, name: "Eski", position: 0, archived_at: Time.utc(2026, 9, 1, 12)) }

    before do
      create(:todo, user: user, todo_list: home)
      create(:todo, user: user, todo_list: home, status: "in_progress")
      create(:todo, user: user, todo_list: home, status: "done")
      create(:todo, user: user, todo_list: old)
      create(:todo, user: user)
      create(:todo, user: user, status: "cancelled")
      create(:todo_list, name: "Someone else's")
    end

    it "lists the active lists by position then name, with their todo counts" do
      get api_v1_todo_lists_path, headers: auth

      expect(response).to have_http_status(:ok)
      expect(body["todo_lists"].map { |list| list["name"] }).to eq([ "İş", "Ev" ])
      expect(body["todo_lists"].last).to eq(
        "id" => home.id, "name" => "Ev", "color" => "#6B8E5A", "position" => 1,
        "archived" => false, "archived_at" => nil, "open_count" => 2, "todos_count" => 3
      )
      expect(body["todo_lists"].first).to include("id" => work.id, "open_count" => 0, "todos_count" => 0)
      expect(body["meta"]).to eq("unlisted_open_count" => 1)
    end

    it "appends the archived lists with include_archived=true" do
      get api_v1_todo_lists_path(include_archived: true), headers: auth

      expect(body["todo_lists"].map { |list| list["name"] }).to eq([ "İş", "Ev", "Eski" ])
      expect(body["todo_lists"].last).to include(
        "archived" => true, "archived_at" => "2026-09-01T12:00:00.000Z", "open_count" => 1, "todos_count" => 1
      )
    end

    it "422s for include_archived that is not a boolean" do
      get api_v1_todo_lists_path(include_archived: "maybe"), headers: auth

      expect(response).to have_http_status(:unprocessable_content)
      expect(body).to include("code" => "invalid_parameter", "param" => "include_archived")
    end
  end

  describe "GET /api/v1/todo_lists/:id" do
    it "returns the list with its counts, archived or not" do
      list = create(:todo_list, user: user, archived_at: Time.current)
      create(:todo, user: user, todo_list: list, status: "done")

      get api_v1_todo_list_path(list), headers: auth

      expect(response).to have_http_status(:ok)
      expect(body["todo_list"]).to include("id" => list.id, "archived" => true, "open_count" => 0, "todos_count" => 1)
    end

    it "404s for another user's list" do
      get api_v1_todo_list_path(create(:todo_list)), headers: auth

      expect(response).to have_http_status(:not_found)
      expect(body).to eq("error" => "not_found", "code" => "not_found")
    end
  end

  describe "POST /api/v1/todo_lists" do
    it "creates an active list with the web form's defaults" do
      expect {
        post api_v1_todo_lists_path, params: { name: "Alışveriş" }, headers: auth, as: :json
      }.to change(user.todo_lists, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(body["todo_list"]).to include(
        "name" => "Alışveriş", "color" => "#B8860B", "position" => 0, "archived" => false,
        "open_count" => 0, "todos_count" => 0
      )
    end

    it "takes a color and a position, and ignores archived" do
      post api_v1_todo_lists_path, params: { name: "Kitaplar", color: "#4a90d9", position: 4, archived: true },
                                   headers: auth, as: :json

      expect(body["todo_list"]).to include("color" => "#4a90d9", "position" => 4, "archived" => false)
    end

    it "422s with every validation error at once" do
      post api_v1_todo_lists_path, params: { name: "", color: "kırmızı" }, headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(body["code"]).to eq("validation_failed")
      expect(body["details"]).to eq("name" => [ { "error" => "blank" } ], "color" => [ { "error" => "invalid" } ])
    end

    it "422s for a name over 60 characters or a null color" do
      post api_v1_todo_lists_path, params: { name: "x" * 61, color: nil }, headers: auth, as: :json

      expect(body["details"]).to eq("name" => [ { "error" => "too_long", "count" => 60 } ], "color" => [ { "error" => "blank" } ])
    end

    it "422s for a position that is not a whole number" do
      expect {
        post api_v1_todo_lists_path, params: { name: "X", position: "first" }, headers: auth, as: :json
      }.not_to change(TodoList, :count)

      expect(body).to include("code" => "invalid_parameter", "param" => "position")
    end

    it "401s without a token" do
      expect { post api_v1_todo_lists_path, params: { name: "X" } }.not_to change(TodoList, :count)

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/todo_lists/:id" do
    let(:list) { create(:todo_list, user: user, name: "Ev", color: "#6B8E5A", position: 2) }

    it "changes only the keys sent" do
      patch api_v1_todo_list_path(list), params: { name: "Ev işleri" }, headers: auth, as: :json

      expect(response).to have_http_status(:ok)
      expect(list.reload).to have_attributes(name: "Ev işleri", color: "#6B8E5A", position: 2)
    end

    it "archives with archived=true, keeping the first archived_at, and restores with archived=false" do
      patch api_v1_todo_list_path(list), params: { archived: true }, headers: auth, as: :json
      archived_at = list.reload.archived_at
      expect(archived_at).to be_present
      expect(body["todo_list"]).to include("archived" => true)

      patch api_v1_todo_list_path(list), params: { archived: true }, headers: auth, as: :json
      expect(list.reload.archived_at).to eq(archived_at)

      patch api_v1_todo_list_path(list), params: { archived: false }, headers: auth, as: :json
      expect(list.reload.archived_at).to be_nil
      expect(body["todo_list"]).to include("archived" => false, "archived_at" => nil)
    end

    it "leaves the list's todos alone when archiving" do
      todo = create(:todo, user: user, todo_list: list)

      patch api_v1_todo_list_path(list), params: { archived: true }, headers: auth, as: :json

      expect(todo.reload.todo_list_id).to eq(list.id)
    end

    it "422s for archived that is not a boolean, or null" do
      [ "maybe", nil ].each do |value|
        patch api_v1_todo_list_path(list), params: { archived: value }, headers: auth, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(body).to include("code" => "invalid_parameter", "param" => "archived")
      end
      expect(list.reload.archived_at).to be_nil
    end

    it "422s for an invalid color and saves nothing" do
      patch api_v1_todo_list_path(list), params: { name: "Yeni", color: "blue" }, headers: auth, as: :json

      expect(body["details"]).to eq("color" => [ { "error" => "invalid" } ])
      expect(list.reload.name).to eq("Ev")
    end

    it "404s for another user's list" do
      other = create(:todo_list, name: "Theirs")

      patch api_v1_todo_list_path(other), params: { name: "Mine" }, headers: auth, as: :json

      expect(response).to have_http_status(:not_found)
      expect(other.reload.name).to eq("Theirs")
    end
  end

  describe "DELETE /api/v1/todo_lists/:id" do
    let!(:list) { create(:todo_list, user: user) }
    let!(:listed) { create(:todo, user: user, todo_list: list) }
    let!(:elsewhere) { create(:todo, user: user) }

    it "deletes the list and its todos by default" do
      delete api_v1_todo_list_path(list), headers: auth

      expect(response).to have_http_status(:no_content)
      expect(TodoList.exists?(list.id)).to be(false)
      expect(Todo.exists?(listed.id)).to be(false)
      expect(Todo.exists?(elsewhere.id)).to be(true)
    end

    it "keeps the todos, without a list, with todos=keep" do
      delete api_v1_todo_list_path(list, todos: "keep"), headers: auth

      expect(response).to have_http_status(:no_content)
      expect(TodoList.exists?(list.id)).to be(false)
      expect(listed.reload.todo_list_id).to be_nil
    end

    it "deletes todos that have focus sessions and subtasks elsewhere" do
      session = create(:focus_session, user: user, todo: listed)
      subtask = create(:todo, user: user, parent: listed)

      delete api_v1_todo_list_path(list, todos: "delete"), headers: auth

      expect(response).to have_http_status(:no_content)
      expect(session.reload.todo_id).to be_nil
      expect(subtask.reload.parent_id).to be_nil
    end

    it "deletes a list's todos and their subtasks in the list with a fixed number of statements" do
      more = create_list(:todo, 5, user: user, todo_list: list)
      create(:todo, user: user, todo_list: list, parent: more.first)
      statements = []
      counter = ->(*, payload) { statements << payload[:sql] if payload[:sql].match?(/\A\s*(UPDATE|DELETE)/i) }

      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        delete api_v1_todo_list_path(list), headers: auth
      end

      expect(response).to have_http_status(:no_content)
      expect(Todo.where(user: user).pluck(:id)).to eq([ elsewhere.id ])
      expect(statements.size).to be <= 4
    end

    it "422s for an unknown todos mode and deletes nothing" do
      delete api_v1_todo_list_path(list, todos: "archive"), headers: auth

      expect(response).to have_http_status(:unprocessable_content)
      expect(body).to include("code" => "invalid_parameter", "param" => "todos")
      expect(TodoList.exists?(list.id)).to be(true)
    end

    it "404s for another user's list and deletes nothing" do
      other = create(:todo_list)
      create(:todo, user: other.user, todo_list: other)

      expect { delete api_v1_todo_list_path(other), headers: auth }.not_to change(Todo, :count)

      expect(response).to have_http_status(:not_found)
      expect(TodoList.exists?(other.id)).to be(true)
    end

    it "401s without a token" do
      delete api_v1_todo_list_path(list)

      expect(response).to have_http_status(:unauthorized)
      expect(TodoList.exists?(list.id)).to be(true)
    end
  end
end
