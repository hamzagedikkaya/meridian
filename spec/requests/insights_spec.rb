require 'rails_helper'

RSpec.describe "Insights", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it "renders the page" do
    get insights_path
    expect(response).to have_http_status(:success)
    expect(response.body).to include("Insights")
  end
end
