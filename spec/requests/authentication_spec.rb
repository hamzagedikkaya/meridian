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

  describe "self-registration" do
    # Meridian is served on a LAN, so an open sign-up form would let anyone on
    # the network mint an account. :registerable is off and the routes are gone.
    it "does not route the sign-up form" do
      get "/users/sign_up"
      expect(response).to have_http_status(:not_found)
    end

    it "does not create a user from a POST to /users" do
      params = {
        user: {
          name: "Test User",
          email: "test@meridian.local",
          password: "password123",
          password_confirmation: "password123"
        }
      }
      expect { post "/users", params: params }.not_to change(User, :count)
      expect(response).to have_http_status(:not_found)
    end

    it "does not offer a sign-up link on the login page" do
      get new_user_session_path
      expect(response.body).not_to include("/users/sign_up")
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
