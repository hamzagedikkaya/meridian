module Api
  module V1
    class SessionsController < BaseController
      include ActionController::RateLimiting

      skip_before_action :authenticate_api_user!, only: :create

      # Devise is not :lockable and there is no Rack::Attack, so without this a
      # 6-character password (the configured minimum) can be guessed at line
      # speed. A dedicated store is used because Rails.cache is the null store
      # in development, which would make the limit silently do nothing.
      RATE_LIMIT_STORE = ActiveSupport::Cache::MemoryStore.new(size: 2.megabytes)

      rate_limit to: 10, within: 5.minutes, only: :create,
                 store: RATE_LIMIT_STORE,
                 with: -> { render json: { error: "too_many_requests" }, status: :too_many_requests }

      def create
        user = User.find_by(email: params[:email].to_s.strip.downcase)
        if user&.valid_password?(params[:password].to_s)
          render json: { token: user.api_token, user: Serialize.user(user) }
        else
          render json: { error: "invalid_credentials" }, status: :unauthorized
        end
      end
    end
  end
end
