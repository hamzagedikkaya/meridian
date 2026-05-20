require 'rails_helper'

RSpec.describe "Authentication", type: :request do
  describe "GET /" do
    context "when not signed in" do
      it "redirects to the sign-in page" do
        get "/"
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "when signed in" do
      let(:user) { create(:user) }

      before { sign_in user }

      it "renders the home page" do
        get "/"
        expect(response).to have_http_status(:success)
        expect(response.body).to include("Meridian")
      end
    end
  end

  describe "GET /users/sign_in" do
    it "renders the sign-in form with the auth layout" do
      get new_user_session_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Welcome back")
      expect(response.body).to include("Your life")  # auth layout brand panel
    end
  end

  describe "GET /users/sign_up" do
    it "renders the registration form" do
      get new_user_registration_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Create your account")
    end
  end

  describe "POST /users" do
    let(:valid_params) do
      {
        user: {
          name: "Test User",
          email: "test@meridian.local",
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end

    it "creates a new user and signs them in" do
      expect { post user_registration_path, params: valid_params }
        .to change(User, :count).by(1)
      expect(response).to redirect_to(root_path)
    end
  end

  describe "DELETE /users/sign_out" do
    let(:user) { create(:user) }

    it "signs the user out and redirects to root" do
      sign_in user
      delete destroy_user_session_path
      expect(response).to redirect_to(root_path)
    end
  end
end
