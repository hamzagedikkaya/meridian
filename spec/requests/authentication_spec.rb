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

  # Devise's paranoid mode: neither web form tells whether an email has an
  # account.
  describe "unknown emails (paranoid mode)" do
    before { create(:user, email: "known@meridian.local", password: "password123", password_confirmation: "password123") }

    it "hashes the password for an unknown email too, so the web sign-in takes as long as for a wrong password" do
      bcrypt_runs = 0
      count = ->(method, *args) { bcrypt_runs += 1; method.call(*args) }
      allow(Devise::Encryptor).to receive(:compare).and_wrap_original(&count)
      allow(Devise::Encryptor).to receive(:digest).and_wrap_original(&count)

      post user_session_path, params: { user: { email: "known@meridian.local", password: "wrong-123" } }
      known_runs = bcrypt_runs
      bcrypt_runs = 0
      post user_session_path, params: { user: { email: "nobody@meridian.local", password: "guess-123" } }

      # As much bcrypt work either way: the known email's compare is matched
      # by a hash of the guess for the unknown one (Devise's paranoid mode).
      expect(known_runs).to be_positive
      expect(bcrypt_runs).to eq(known_runs)
      expect(flash[:alert]).to eq("Invalid email or password.")
    end

    it "gives a wrong password the same message as an unknown email" do
      post user_session_path, params: { user: { email: "known@meridian.local", password: "wrong-123" } }
      known = flash[:alert]
      post user_session_path, params: { user: { email: "nobody@meridian.local", password: "wrong-123" } }

      expect(flash[:alert]).to eq(known)
    end

    it "answers the password-reset form the same way for an unknown and a known email" do
      post user_password_path, params: { user: { email: "nobody@meridian.local" } }
      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:notice]).to eq(I18n.t("devise.passwords.send_paranoid_instructions"))

      expect {
        post user_password_path, params: { user: { email: "known@meridian.local" } }
      }.to change(ActionMailer::Base.deliveries, :size).by(1)
      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:notice]).to eq(I18n.t("devise.passwords.send_paranoid_instructions"))
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
