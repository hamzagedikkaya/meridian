module Api
  module V1
    class MeController < BaseController
      def show
        render json: { user: Serialize.user(current_user) }
      end
    end
  end
end
