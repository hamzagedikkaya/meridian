require 'rails_helper'

RSpec.describe "Finance::Dashboard", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it "renders the dashboard" do
    get finance_root_path
    expect(response).to have_http_status(:success)
    expect(response.body).to include("Finance")
  end
end
