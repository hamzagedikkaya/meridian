module Users
  # Devise's web sign-in with the API login's limits
  # (Api::V1::SessionsController): Devise is not :lockable, so without them a
  # password could be guessed from the LAN without end.
  class SessionsController < Devise::SessionsController
    include ClientAddress

    # Prepended, so they run before any other callback: Devise's prepended
    # allow_params_authentication! lets Warden read the password from the
    # params, and then ApplicationController's around_action
    # switch_time_zone_and_locale calls current_user, which runs that params
    # strategy, checking the password and signing the user in before an
    # ordinary before_action would run. (require_no_authentication only runs
    # the :rememberable strategy.)
    rate_limit to: 10, within: 5.minutes, only: :create, prepend: true,
               by: -> { client_ip }, store: Api::V1::SessionsController::RATE_LIMIT_STORE,
               with: -> { refuse_sign_in }
    rate_limit to: 10, within: 5.minutes, only: :create, name: "per_email", prepend: true,
               by: -> { sign_in_email }, store: Api::V1::SessionsController::RATE_LIMIT_STORE,
               with: -> { refuse_sign_in }

    private

    def sign_in_email
      email = params[:user].is_a?(ActionController::Parameters) ? params[:user][:email] : nil
      email.is_a?(String) ? email.strip.downcase : ""
    end

    def refuse_sign_in
      redirect_to new_user_session_path, alert: t("devise.failure.too_many_attempts"), status: :see_other
    end
  end
end
