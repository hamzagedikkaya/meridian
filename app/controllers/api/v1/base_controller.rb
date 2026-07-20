module Api
  module V1
    class BaseController < ActionController::API
      before_action :authenticate_api_user!

      rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

      private

      attr_reader :current_user

      def authenticate_api_user!
        @current_user = User.find_by(api_token: bearer_token) if bearer_token.present?
        return if @current_user

        render json: { error: "unauthorized" }, status: :unauthorized
      end

      def bearer_token
        request.authorization.to_s[/\ABearer (.+)\z/, 1]
      end

      def render_not_found
        render json: { error: "not_found" }, status: :not_found
      end

      def render_errors(record)
        render json: { errors: record.errors.to_hash(true) }, status: :unprocessable_entity
      end
    end
  end
end
