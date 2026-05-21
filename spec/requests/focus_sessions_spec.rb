require 'rails_helper'

RSpec.describe "FocusSessions", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "POST /focus_sessions" do
    it "starts a new focus session" do
      expect {
        post focus_sessions_path, params: { duration_minutes: 25, mode: "focus" }, as: :json
      }.to change(FocusSession, :count).by(1)
      expect(JSON.parse(response.body)["duration_seconds"]).to eq(1500)
    end

    it "links to a todo when todo_id is provided" do
      todo = create(:todo, user: user)
      post focus_sessions_path, params: { duration_minutes: 25, todo_id: todo.id, mode: "focus" }, as: :json
      expect(FocusSession.last.todo_id).to eq(todo.id)
    end
  end

  describe "PATCH /focus_sessions/:id" do
    let(:session) { create(:focus_session, user: user, completed_at: nil) }

    it "marks the session completed" do
      patch focus_session_path(session)
      expect(session.reload.completed_at).to be_present
    end
  end
end
