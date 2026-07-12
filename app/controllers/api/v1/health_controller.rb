module Api
  module V1
    class HealthController < BaseController
      skip_before_action :authenticate_api_user!

      def show
        render json: { ok: true, app: "meridian", version: "1.0.0" }
      end
    end
  end
end
