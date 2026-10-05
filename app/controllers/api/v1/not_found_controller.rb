module Api
  module V1
    # Every /api/v1 path no route matches (the catch-all in config/routes.rb):
    # the API's JSON 404, with or without a token, instead of Rails' HTML page.
    class NotFoundController < BaseController
      skip_before_action :authenticate_api_user!

      def show
        render_not_found
      end
    end
  end
end
