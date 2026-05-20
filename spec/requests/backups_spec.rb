require 'rails_helper'

RSpec.describe "Backups", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /backups" do
    it "renders" do
      get backups_path
      expect(response).to have_http_status(:success)
    end
  end
end
