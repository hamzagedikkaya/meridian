module Api
  module V1
    class SessionsController < BaseController
      include ActionController::RateLimiting

      skip_before_action :authenticate_api_user!, only: :create

      # Devise is not :lockable and there is no Rack::Attack, so without these
      # a 6-character password (the configured minimum) can be guessed at line
      # speed. A dedicated store is used because Rails.cache is the null store
      # in development, which would make the limit silently do nothing.
      RATE_LIMIT_STORE = ActiveSupport::Cache::MemoryStore.new(size: 2.megabytes)

      # Per address (BaseController#client_ip, which a forged X-Forwarded-For
      # cannot move), and per email, which no choice of address avoids.
      rate_limit to: 10, within: 5.minutes, only: :create,
                 by: -> { client_ip }, store: RATE_LIMIT_STORE,
                 with: -> { render_too_many_requests }
      rate_limit to: 10, within: 5.minutes, only: :create, name: "per_email",
                 by: -> { login_email }, store: RATE_LIMIT_STORE,
                 with: -> { render_too_many_requests }

      def self.dummy_digest
        @dummy_digest ||= Devise::Encryptor.digest(User, SecureRandom.hex(16)).freeze
      end

      def create
        user = User.find_by(email: login_email)
        if password_matches?(user, params[:password].to_s)
          render json: { token: user.api_token, user: Serialize.user(user) }
        else
          render json: { error: "invalid_credentials", code: "invalid_credentials" }, status: :unauthorized
        end
      end

      # Signs out by replacing the caller's token, so a copy of it left on the
      # phone (or anywhere else) stops working. There is one token per user
      # (users.api_token), so this signs out every device; the next
      # POST /session returns the new token.
      def destroy
        current_user.rotate_api_token!
        head :no_content
      end

      private

      # When no user has the email, a password is still compared, with a
      # digest of the same cost, so an unknown address takes as long to
      # refuse as a wrong password and the timing does not tell which emails
      # have accounts.
      def password_matches?(user, password)
        return user.valid_password?(password) if user

        Devise::Encryptor.compare(User, self.class.dummy_digest, password)
        false
      end

      def login_email
        params[:email].is_a?(String) ? params[:email].strip.downcase : ""
      end
    end
  end
end
