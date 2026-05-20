require 'rails_helper'

RSpec.describe "WeeklyReviews", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /weekly_reviews" do
    it "renders" do
      get weekly_reviews_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /weekly_reviews" do
    it "creates a review" do
      expect {
        post weekly_reviews_path, params: { weekly_review: { week_starting: Date.current.beginning_of_week, reflection_went_well: "All good" } }
      }.to change(WeeklyReview, :count).by(1)
    end
  end
end
