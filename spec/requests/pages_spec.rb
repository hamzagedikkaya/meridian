require 'rails_helper'

RSpec.describe "Pages", type: :request do
  describe "GET /" do
    it "returns http success and renders the welcome shell" do
      get "/"
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Meridian")
    end
  end
end
