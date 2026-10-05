require "rails_helper"

RSpec.describe "Api::V1::Me", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, locale: "tr", theme_preference: "dark") }
  let(:auth) { { "Authorization" => "Bearer #{user.api_token}" } }

  def body = JSON.parse(response.body)
  def auth_for(token) = { "Authorization" => "Bearer #{token}" }

  describe "GET /api/v1/me" do
    it "returns JSON 401 without a token" do
      get api_v1_me_path

      expect(response).to have_http_status(:unauthorized)
      expect(response.media_type).to eq("application/json")
      expect(JSON.parse(response.body)["error"]).to eq("unauthorized")
    end

    it "returns the profile the mobile client renders" do
      user.update!(weekly_review_day: 5)

      get api_v1_me_path, headers: auth

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["user"]).to include(
        "id" => user.id,
        "email" => user.email,
        "display_name" => user.display_name,
        "initials" => user.initials,
        "currency" => user.currency,
        "locale" => "tr",
        "theme_preference" => "dark",
        "weekly_review_day" => 5
      )
    end
  end

  describe "PATCH /api/v1/me" do
    it "persists the language and theme chosen on the phone" do
      patch api_v1_me_path, params: { locale: "en", theme_preference: "light" }, headers: auth

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["user"]).to include(
        "locale" => "en",
        "theme_preference" => "light"
      )
      expect(user.reload.locale).to eq("en")
      expect(user.theme_preference).to eq("light")
    end

    it "accepts a partial update" do
      patch api_v1_me_path, params: { locale: "en" }, headers: auth

      expect(response).to have_http_status(:ok)
      expect(user.reload.locale).to eq("en")
      expect(user.theme_preference).to eq("dark")
    end

    it "changes every other setting of the web's settings pages" do
      patch api_v1_me_path,
        params: { name: "Hamza Gedik", currency: "USD", timezone: "London", weekly_review_day: 1 },
        headers: auth, as: :json

      expect(response).to have_http_status(:ok)
      expect(body["user"]).to include(
        "name" => "Hamza Gedik", "display_name" => "Hamza Gedik", "initials" => "HG",
        "currency" => "USD", "subunit_to_unit" => 100,
        "timezone" => "London", "timezone_iana" => "Europe/London",
        "weekly_review_day" => 1
      )
      expect(user.reload).to have_attributes(name: "Hamza Gedik", currency: "USD", timezone: "London", weekly_review_day: 1)
    end

    it "changes nothing but the caller's own record" do
      other = create(:user, name: "Other", currency: "TRY")

      patch api_v1_me_path, params: { name: "Renamed", currency: "EUR" }, headers: auth, as: :json

      expect(response).to have_http_status(:ok)
      expect(other.reload).to have_attributes(name: "Other", currency: "TRY")
    end

    it "ignores fields the client may not change here" do
      token = user.api_token

      patch api_v1_me_path,
        params: { locale: "en", password: "hijacked1", password_confirmation: "hijacked1",
                  api_token: "chosen-token", encrypted_password: "x", id: 999 },
        headers: auth, as: :json

      expect(response).to have_http_status(:ok)
      expect(user.reload.locale).to eq("en")
      expect(user.api_token).to eq(token)
      expect(user.valid_password?("password123")).to be(true)
    end

    it "still accepts the body nested under user, like the web form" do
      patch api_v1_me_path, params: { user: { name: "Nested", weekly_review_day: 2 } }, headers: auth, as: :json

      expect(response).to have_http_status(:ok)
      expect(user.reload).to have_attributes(name: "Nested", weekly_review_day: 2)
    end

    it "422s with field errors on an unsupported locale" do
      patch api_v1_me_path, params: { locale: "de" }, headers: auth

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["errors"]).to have_key("locale")
      expect(user.reload.locale).to eq("tr")
    end

    it "422s for a theme the web does not offer" do
      patch api_v1_me_path, params: { theme_preference: "sepia" }, headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(body["details"]["theme_preference"]).to eq([ { "error" => "inclusion", "value" => "sepia" } ])
    end

    it "validates the name like the model, in the user's language" do
      patch api_v1_me_path, params: { name: " " }, headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(body).to include("code" => "validation_failed", "errors" => { "name" => [ "Ad boş bırakılamaz" ] })

      patch api_v1_me_path, params: { name: "a" * 81 }, headers: auth, as: :json

      expect(body["details"]["name"]).to eq([ { "error" => "too_long", "count" => 80 } ])
      expect(user.reload.name).not_to eq("a" * 81)
    end

    it "401s without a token" do
      patch api_v1_me_path, params: { locale: "en" }

      expect(response).to have_http_status(:unauthorized)
      expect(user.reload.locale).to eq("tr")
    end

    describe "currency" do
      it "trims and upper-cases the code" do
        patch api_v1_me_path, params: { currency: " gau " }, headers: auth, as: :json

        expect(response).to have_http_status(:ok)
        expect(body["user"]).to include("currency" => "GAU", "subunit_to_unit" => 1)
        expect(user.reload.currency).to eq("GAU")
      end

      it "422s for a code Money does not know, which the web would crash on" do
        patch api_v1_me_path, params: { currency: "xyz" }, headers: auth, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(body["code"]).to eq("validation_failed")
        expect(body["details"]["currency"]).to eq([ { "error" => "inclusion", "value" => "XYZ" } ])
        expect(user.reload.currency).to eq("TRY")
      end

      it "422s for a code that is not three letters" do
        patch api_v1_me_path, params: { currency: "EURO" }, headers: auth, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(body["details"]["currency"].map { |detail| detail["error"] }).to include("wrong_length")
      end

      it "leaves a stored code alone when another field changes" do
        user.update_column(:currency, "XYZ")

        patch api_v1_me_path, params: { theme_preference: "light" }, headers: auth, as: :json

        expect(response).to have_http_status(:ok)
        expect(user.reload).to have_attributes(currency: "XYZ", theme_preference: "light")
      end
    end

    describe "timezone" do
      it "takes the Rails zone names the web offers" do
        patch api_v1_me_path, params: { timezone: "Pacific Time (US & Canada)" }, headers: auth, as: :json

        expect(response).to have_http_status(:ok)
        expect(body["user"]).to include("timezone" => "Pacific Time (US & Canada)", "timezone_iana" => "America/Los_Angeles")
      end

      it "stores a device's IANA id as the Rails zone that uses it" do
        { "Europe/Istanbul" => "Istanbul", "Europe/London" => "London", "Asia/Kolkata" => "Kolkata",
          "America/New_York" => "Eastern Time (US & Canada)", "Etc/UTC" => "UTC" }.each do |iana, name|
          patch api_v1_me_path, params: { timezone: iana }, headers: auth, as: :json

          expect(response).to have_http_status(:ok)
          expect(body["user"]["timezone"]).to eq(name)
          expect(user.reload.timezone).to eq(name)
        end
      end

      it "422s for anything else" do
        [ "Mars/Olympus", "istanbul", "America/Toronto", "../../etc/passwd" ].each do |zone|
          patch api_v1_me_path, params: { timezone: zone }, headers: auth, as: :json

          expect(response).to have_http_status(:unprocessable_content)
          expect(body["details"]["timezone"]).to eq([ { "error" => "inclusion", "value" => zone } ])
        end
        expect(user.reload.timezone).to eq("UTC")
      end
    end

    describe "weekly_review_day" do
      it "takes 0 (Sunday) to 6 as a JSON number or a string of digits" do
        patch api_v1_me_path, params: { weekly_review_day: 6 }, headers: auth, as: :json
        expect(user.reload.weekly_review_day).to eq(6)

        patch api_v1_me_path, params: { weekly_review_day: "3" }, headers: auth
        expect(response).to have_http_status(:ok)
        expect(user.reload.weekly_review_day).to eq(3)
      end

      it "422s invalid_parameter for a value that is not a whole number, instead of saving Sunday" do
        [ "Friday", 1.5, "" ].each do |value|
          patch api_v1_me_path, params: { weekly_review_day: value, name: "Not saved" }, headers: auth, as: :json

          expect(response).to have_http_status(:unprocessable_content)
          expect(body).to include("code" => "invalid_parameter", "param" => "weekly_review_day")
        end
        expect(user.reload.name).not_to eq("Not saved")
      end

      it "422s validation_failed outside 0..6" do
        patch api_v1_me_path, params: { weekly_review_day: 7 }, headers: auth, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(body["details"]["weekly_review_day"]).to eq([ { "error" => "inclusion", "value" => 7 } ])
      end
    end

    describe "email" do
      it "changes the email when the current password comes with it" do
        token = user.api_token

        patch api_v1_me_path, params: { email: " New@Example.com ", current_password: "password123" }, headers: auth, as: :json

        expect(response).to have_http_status(:ok)
        expect(body["user"]["email"]).to eq("new@example.com")
        expect(user.reload.email).to eq("new@example.com")
        expect(user.api_token).to eq(token)
      end

      it "422s current_password_required without the current password" do
        email = user.email

        patch api_v1_me_path, params: { email: "new@example.com" }, headers: auth, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(body).to include(
          "code" => "current_password_required",
          "errors" => { "current_password" => [ "Mevcut şifre boş bırakılamaz" ] },
          "details" => { "current_password" => [ { "error" => "blank" } ] }
        )
        expect(user.reload.email).to eq(email)
      end

      it "422s invalid_current_password for a wrong one, listing the other errors too" do
        email = user.email

        patch api_v1_me_path, params: { email: "new@example.com", current_password: "wrong-one", name: "" }, headers: auth, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(body["code"]).to eq("invalid_current_password")
        expect(body["details"]).to eq(
          "current_password" => [ { "error" => "invalid" } ],
          "name" => [ { "error" => "blank" } ]
        )
        expect(user.reload.email).to eq(email)
      end

      it "needs no password when the address only differs in case or spaces" do
        patch api_v1_me_path, params: { email: " #{user.email.upcase} ", name: "Same Email" }, headers: auth, as: :json

        expect(response).to have_http_status(:ok)
        expect(user.reload.name).to eq("Same Email")
      end

      it "checks the format and that no other account uses the address" do
        create(:user, email: "taken@example.com")

        patch api_v1_me_path, params: { email: "not-an-email", current_password: "password123" }, headers: auth, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(body).to include("code" => "validation_failed", "details" => { "email" => [ { "error" => "invalid", "value" => "not-an-email" } ] })

        patch api_v1_me_path, params: { email: "Taken@Example.com", current_password: "password123" }, headers: auth, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(body).to include("code" => "validation_failed", "details" => { "email" => [ { "error" => "taken", "value" => "taken@example.com" } ] })
      end

      it "does not say whether an address is taken to a caller without the right password" do
        create(:user, email: "taken@example.com")

        patch api_v1_me_path, params: { email: "taken@example.com" }, headers: auth, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(body["code"]).to eq("current_password_required")
        expect(body["details"]).to eq("current_password" => [ { "error" => "blank" } ])
        expect(body["errors"].keys).to eq([ "current_password" ])

        patch api_v1_me_path, params: { email: "taken@example.com", current_password: "wrong-one" }, headers: auth, as: :json

        expect(body["details"]).to eq("current_password" => [ { "error" => "invalid" } ])
      end

      it "422s taken when another account claims the address between the check and the write" do
        allow(User).to receive(:find_by).and_call_original
        allow(User).to receive(:find_by).with(api_token: user.api_token).and_return(user)
        allow(user).to receive(:save).and_raise(ActiveRecord::RecordNotUnique)

        patch api_v1_me_path, params: { email: "Race@Example.com", current_password: "password123" }, headers: auth, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(body).to include("code" => "validation_failed", "details" => { "email" => [ { "error" => "taken", "value" => "race@example.com" } ] })
      end

      it "422s invalid_parameter for a current_password that is not a string" do
        patch api_v1_me_path, params: { email: "new@example.com", current_password: 123 }, headers: auth, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(body).to include("code" => "invalid_parameter", "param" => "current_password")
      end
    end

    describe "rate limit on current password checks" do
      before { Api::V1::MeController::PASSWORD_CHECK_STORE.clear }

      it "429s after 10 requests with a current password in 5 minutes" do
        10.times do
          patch api_v1_me_path, params: { email: "new@example.com", current_password: "guess" }, headers: auth, as: :json
          expect(response).to have_http_status(:unprocessable_content)
        end

        patch api_v1_me_path, params: { email: "new@example.com", current_password: "password123" }, headers: auth, as: :json

        expect(response).to have_http_status(:too_many_requests)
        expect(body).to eq("error" => "too_many_requests", "code" => "too_many_requests")
        expect(user.reload.email).not_to eq("new@example.com")
      end

      it "keeps other updates, and other users, going once the limit is reached" do
        10.times { patch api_v1_me_path, params: { email: "new@example.com", current_password: "guess" }, headers: auth, as: :json }

        patch api_v1_me_path, params: { theme_preference: "light" }, headers: auth, as: :json
        expect(response).to have_http_status(:ok)

        other = create(:user)
        patch api_v1_me_path, params: { email: "other@example.com", current_password: "password123" }, headers: auth_for(other.api_token), as: :json
        expect(response).to have_http_status(:ok)
      end

      it "does not count updates without a current password" do
        12.times do |i|
          patch api_v1_me_path, params: { weekly_review_day: i % 7 }, headers: auth, as: :json
          expect(response).to have_http_status(:ok)
        end
      end
    end
  end

  describe "GET /api/v1/me/options" do
    it "401s without a token" do
      get api_v1_me_options_path

      expect(response).to have_http_status(:unauthorized)
      expect(body).to eq("error" => "unauthorized", "code" => "unauthorized")
    end

    it "offers the currencies of GET /currencies, the user's own included" do
      user.update!(currency: "CHF")

      get api_v1_me_options_path, headers: auth

      expect(response).to have_http_status(:ok)
      expect(body["currencies"].map { |c| c["code"] }).to eq(%w[TRY USD EUR GBP GAU CHF])
      expect(body["currencies"].first).to eq(
        "code" => "TRY", "name" => "Türk lirası", "symbol" => "₺", "symbol_first" => true,
        "subunit_to_unit" => 100, "decimal_places" => 2
      )
    end

    it "lists every zone the model accepts, with the web's label, IANA id and current offset" do
      travel_to Time.utc(2026, 7, 1, 12)

      get api_v1_me_options_path, headers: auth

      zones = body["timezones"]
      expect(zones.map { |z| z["value"] }).to eq(ActiveSupport::TimeZone.all.map(&:name))
      expect(zones.find { |z| z["value"] == "Istanbul" }).to eq(
        "value" => "Istanbul", "name" => "(GMT+03:00) Istanbul", "iana" => "Europe/Istanbul", "utc_offset" => "+03:00"
      )
      expect(zones.find { |z| z["value"] == "London" }).to eq(
        "value" => "London", "name" => "(GMT+00:00) London", "iana" => "Europe/London", "utc_offset" => "+01:00"
      )
    end

    it "labels languages in their own name, and themes and review days in the user's language" do
      get api_v1_me_options_path, headers: auth

      expect(body["locales"]).to eq([ { "value" => "tr", "name" => "Türkçe" }, { "value" => "en", "name" => "English" } ])
      expect(body["theme_preferences"]).to eq([
        { "value" => "dark", "name" => "Koyu" },
        { "value" => "light", "name" => "Açık" },
        { "value" => "system", "name" => "Sistemi takip et" }
      ])
      expect(body["weekly_review_days"].first(2)).to eq([ { "value" => 0, "name" => "Pazar" }, { "value" => 1, "name" => "Pazartesi" } ])
      expect(body["weekly_review_days"].map { |d| d["value"] }).to eq((0..6).to_a)
    end

    it "labels them in English for an English user" do
      user.update!(locale: "en")

      get api_v1_me_options_path, headers: auth

      expect(body["weekly_review_days"].last).to eq("value" => 6, "name" => "Saturday")
      expect(body["theme_preferences"].last).to eq("value" => "system", "name" => "Follow system")
      expect(body["currencies"].first["name"]).to eq("Turkish lira")
    end
  end

  describe "PATCH /api/v1/me/password" do
    let(:new_password) { { current_password: "password123", password: "new-secret-1", password_confirmation: "new-secret-1" } }

    before { Api::V1::MeController::PASSWORD_CHECK_STORE.clear }

    it "changes the password and answers with a new token" do
      old_token = user.api_token

      patch api_v1_me_password_path, params: new_password, headers: auth, as: :json

      expect(response).to have_http_status(:ok)
      expect(body["token"]).to be_present.and(satisfy { |token| token != old_token })
      expect(body["user"]).to include("id" => user.id, "email" => user.email)
      expect(user.reload.api_token).to eq(body["token"])
      expect(user.valid_password?("new-secret-1")).to be(true)
    end

    it "keeps this client signed in with the new token and signs the old one out" do
      old_token = user.api_token
      patch api_v1_me_password_path, params: new_password, headers: auth, as: :json
      new_token = body["token"]

      get api_v1_me_path, headers: auth_for(old_token)
      expect(response).to have_http_status(:unauthorized)

      get api_v1_me_path, headers: auth_for(new_token)
      expect(response).to have_http_status(:ok)
    end

    it "signs the user out of the web too" do
      sign_in user
      get profile_settings_path
      expect(response).to have_http_status(:ok)

      patch api_v1_me_password_path, params: new_password, headers: auth, as: :json
      expect(response).to have_http_status(:ok)

      get profile_settings_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "leaves other users signed in" do
      other = create(:user)

      patch api_v1_me_password_path, params: new_password, headers: auth, as: :json

      get api_v1_me_path, headers: auth_for(other.api_token)
      expect(response).to have_http_status(:ok)
      expect(other.reload.valid_password?("password123")).to be(true)
    end

    it "422s invalid_current_password for a wrong current password and changes nothing" do
      token = user.api_token

      patch api_v1_me_password_path, params: new_password.merge(current_password: "wrong-one"), headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(body).to eq(
        "errors" => { "current_password" => [ "Mevcut şifre geçersiz" ] },
        "code" => "invalid_current_password",
        "details" => { "current_password" => [ { "error" => "invalid" } ] }
      )
      expect(user.reload.api_token).to eq(token)
      expect(user.valid_password?("password123")).to be(true)
    end

    it "422s current_password_required without the current password" do
      patch api_v1_me_password_path, params: new_password.except(:current_password), headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(body["code"]).to eq("current_password_required")
      expect(body["details"]).to eq("current_password" => [ { "error" => "blank" } ])
      expect(user.reload.valid_password?("password123")).to be(true)
    end

    it "422s for a blank new password, which Devise alone would report as a success" do
      token = user.api_token

      patch api_v1_me_password_path, params: { current_password: "password123", password: "", password_confirmation: "" }, headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(body["code"]).to eq("validation_failed")
      expect(body["details"]).to eq("password" => [ { "error" => "blank" } ])
      expect(user.reload.api_token).to eq(token)
    end

    it "reports a wrong current password together with the other errors" do
      patch api_v1_me_password_path, params: { current_password: "wrong-one" }, headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(body["code"]).to eq("invalid_current_password")
      expect(body["details"]).to eq("password" => [ { "error" => "blank" } ], "current_password" => [ { "error" => "invalid" } ])
    end

    it "422s when the confirmation is missing or different" do
      patch api_v1_me_password_path, params: new_password.except(:password_confirmation), headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(body["code"]).to eq("validation_failed")
      expect(body["details"]["password_confirmation"].first["error"]).to eq("confirmation")

      patch api_v1_me_password_path, params: new_password.merge(password_confirmation: "new-secret-2"), headers: auth, as: :json

      expect(body["details"]["password_confirmation"].first["error"]).to eq("confirmation")
      expect(user.reload.valid_password?("password123")).to be(true)
    end

    it "422s for a password shorter than Devise's minimum" do
      patch api_v1_me_password_path, params: { current_password: "password123", password: "abc", password_confirmation: "abc" }, headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(body["details"]).to eq("password" => [ { "error" => "too_short", "count" => 6 } ])
    end

    it "422s invalid_parameter for a value that is not a string" do
      patch api_v1_me_password_path, params: new_password.merge(password: 12345678, password_confirmation: 12345678), headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(body).to include("code" => "invalid_parameter", "param" => "password")
    end

    it "429s after 10 attempts in 5 minutes, even with the right password" do
      10.times do
        patch api_v1_me_password_path, params: new_password.merge(current_password: "guess"), headers: auth, as: :json
        expect(response).to have_http_status(:unprocessable_content)
      end

      patch api_v1_me_password_path, params: new_password, headers: auth, as: :json

      expect(response).to have_http_status(:too_many_requests)
      expect(body).to eq("error" => "too_many_requests", "code" => "too_many_requests")
      expect(user.reload.valid_password?("password123")).to be(true)
    end

    it "shares the limit with email changes" do
      10.times { patch api_v1_me_path, params: { email: "new@example.com", current_password: "guess" }, headers: auth, as: :json }

      patch api_v1_me_password_path, params: new_password, headers: auth, as: :json

      expect(response).to have_http_status(:too_many_requests)
    end

    it "401s without a token and changes nothing" do
      patch api_v1_me_password_path, params: new_password, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(body).to eq("error" => "unauthorized", "code" => "unauthorized")
      expect(user.reload.valid_password?("password123")).to be(true)
    end
  end
end
