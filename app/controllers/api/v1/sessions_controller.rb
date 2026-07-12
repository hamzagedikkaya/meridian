module Api
  module V1
    class SessionsController < BaseController
      skip_before_action :authenticate_api_user!, only: :create

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
