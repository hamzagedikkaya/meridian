module Api
  module V1
    class MeController < BaseController
      include ActionController::RateLimiting

      # Every request that checks the current password counts, per user, so
      # a stolen token cannot be used to guess the password behind it (the
      # login limits count per address and per email, not per token). A
      # dedicated store for the same reason as
      # SessionsController::RATE_LIMIT_STORE.
      PASSWORD_CHECK_STORE = ActiveSupport::Cache::MemoryStore.new(size: 1.megabyte)

      rate_limit to: 10, within: 5.minutes, name: "password_check",
                 by: -> { current_user.id }, store: PASSWORD_CHECK_STORE,
                 only: [ :update, :update_password ], if: :checks_password?,
                 with: -> { render_too_many_requests }

      # Each language in its own name, as the web's language select shows it.
      LOCALE_NAMES = { "tr" => "Türkçe", "en" => "English" }.freeze

      def show
        render json: { user: Serialize.user(current_user) }
      end

      # What the web's profile and preferences pages change
      # (SettingsController#profile_params and #preferences_params), without
      # the avatar upload, and the password, which has its own endpoint. Only
      # the keys sent change.
      #
      # Stricter than the web: a new email needs the current password. The
      # email is the login, so a token alone (a lost phone) must not be
      # enough to take the account over.
      def update
        attributes = me_attributes
        current_password = string_param(:current_password, from: me_source)
        current_user.assign_attributes(attributes)

        saved = save_checked(current_user) do |user|
          check_currency(user)
          # After validation, so Devise has stripped and downcased the email:
          # the same address in other letter case is not a change.
          check_email_change(user, current_password) if user.will_save_change_to_email?
        end

        if saved
          render json: { user: Serialize.user(current_user) }
        else
          render_errors(current_user, code: password_error_code(current_user))
        end
      rescue ActiveRecord::RecordNotUnique
        # Another account took the email between the uniqueness check and the
        # write (users.email has a unique index). Same detail as the check's.
        current_user.errors.add(:email, :taken, value: current_user.email)
        render_errors(current_user)
      end

      # The choices behind the profile pickers. Labels are in the user's
      # language; the currencies are those of GET /currencies.
      def options
        render json: {
          currencies: CurrenciesController.offered_to(current_user).map { |currency| Serialize.currency(currency) },
          timezones: ActiveSupport::TimeZone.all.map { |zone| Serialize.time_zone(zone) },
          locales: User::SUPPORTED_LOCALES.map { |code| { value: code, name: LOCALE_NAMES.fetch(code, code) } },
          theme_preferences: User::THEME_PREFERENCES.map do |theme|
            { value: theme, name: I18n.t("settings.preferences.theme_#{theme}") }
          end,
          weekly_review_days: User::WEEKLY_REVIEW_DAYS.map { |day| { value: day, name: I18n.t("date.day_names")[day] } }
        }
      end

      # Devise's update_with_password: the current password must match, and
      # on a mismatch every field is still validated so all errors come back
      # together. Two gaps are closed first: it reads a blank password as
      # "keep the current one" and reports success, and it never compares a
      # confirmation that was not sent (hence to_s: a missing one is "").
      #
      # On success the API token is replaced (User#replace_api_token, as for
      # every password change), signing out every other device, and the new
      # one is returned so this client stays signed in. Devise also ends web
      # sessions, which are tied to the password hash.
      def update_password
        attributes = {
          current_password: string_param(:current_password),
          password: string_param(:password),
          password_confirmation: string_param(:password_confirmation)
        }.transform_values(&:to_s)

        if attributes[:password].blank?
          current_user.errors.add(:password, :blank)
          check_current_password(current_user, attributes[:current_password])
          return render_errors(current_user, code: password_error_code(current_user))
        end

        if current_user.update_with_password(attributes)
          render json: { token: current_user.api_token, user: Serialize.user(current_user) }
        else
          render_errors(current_user, code: password_error_code(current_user))
        end
      end

      private

      # Flat, or nested under "user" as the web's form posts it; PATCH /me
      # took both before, so both stay.
      def me_source
        params[:user].is_a?(ActionController::Parameters) ? params[:user] : params
      end

      def me_attributes
        attributes = me_source.permit(:name, :email, :currency, :timezone, :locale, :theme_preference).to_h
        # The web's currency field only looks upper-case (CSS); Money and
        # every amount label need the real ISO code.
        attributes[:currency] = attributes[:currency].strip.upcase if attributes[:currency].is_a?(String)
        attributes[:timezone] = rails_time_zone_name(attributes[:timezone]) if attributes[:timezone].is_a?(String)
        # The integer column would read "abc" as 0 (Sunday).
        attributes[:weekly_review_day] = integer_param(:weekly_review_day, from: me_source) if me_source.key?(:weekly_review_day)
        attributes
      end

      # The model accepts only the Rails zone names the web's time zone select
      # offers ("Istanbul"). A phone knows its zone by IANA id
      # ("Europe/Istanbul"), so an id that one of those zones uses is stored
      # as that zone's name. Where several share it, the one named after the
      # id's city wins ("Europe/London" is "London", not "Edinburgh").
      # Anything else is left for the model's inclusion check to refuse.
      def rails_time_zone_name(value)
        return value if ActiveSupport::TimeZone::MAPPING.key?(value) || !value.include?("/")

        canonical = TZInfo::Timezone.get(value).canonical_identifier
        zones = ActiveSupport::TimeZone.all.select { |zone| zone.tzinfo.canonical_identifier == canonical }
        city = value.split("/").last.tr("_", " ")
        (zones.find { |zone| zone.name == city } || zones.first)&.name || value
      rescue TZInfo::InvalidTimezoneIdentifier
        value
      end

      # The user model only checks the length, and the web prints amounts with
      # Money.new(cents, currency), which raises for a code Money does not
      # know. Checked only on a change, like an account's currency
      # (AccountsController#check_account).
      def check_currency(user)
        return unless user.will_save_change_to_currency? && user.currency.present?

        user.errors.add(:currency, :inclusion, value: user.currency) unless Money::Currency.find(user.currency)
      end

      # A new email needs the current password. Without it, or with a wrong
      # one, the uniqueness check's "taken" is dropped: a token alone must
      # not tell whether an address belongs to another account.
      def check_email_change(user, password)
        check_current_password(user, password)
        user.errors.delete(:email, :taken) if user.errors.include?(:current_password)
      end

      # The errors Devise's update_with_password adds on a mismatch.
      def check_current_password(user, password)
        if password.blank?
          user.errors.add(:current_password, :blank)
        elsif !user.valid_password?(password)
          user.errors.add(:current_password, :invalid)
        end
      end

      def password_error_code(user)
        if user.errors.added?(:current_password, :blank)
          :current_password_required
        elsif user.errors.added?(:current_password, :invalid)
          :invalid_current_password
        else
          :validation_failed
        end
      end

      # The rate limit counts what can check a password: every password
      # change, and a profile update that sends current_password.
      def checks_password?
        action_name == "update_password" || !me_source[:current_password].nil?
      end
    end
  end
end
