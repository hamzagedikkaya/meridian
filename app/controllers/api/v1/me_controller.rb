module Api
  module V1
    class MeController < BaseController
      def show
        render json: { user: Serialize.user(current_user) }
      end

      def update
        if current_user.update(me_params)
          render json: { user: Serialize.user(current_user) }
        else
          render_errors(current_user)
        end
      end

      private

      def me_params
        source = params[:user].is_a?(ActionController::Parameters) ? params[:user] : params
        source.permit(:locale, :theme_preference)
      end
    end
  end
end
