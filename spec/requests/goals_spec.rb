require 'rails_helper'

RSpec.describe "Goals", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /goals" do
    it "renders" do
      get goals_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /goals" do
    it "creates a goal" do
      expect {
        post goals_path, params: { goal: { name: "Save", target_type: "custom", target_value: 100, unit: "TRY", status: "active" } }
      }.to change(Goal, :count).by(1)
    end
  end
end
