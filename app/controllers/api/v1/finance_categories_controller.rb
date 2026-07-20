module Api
  module V1
    class FinanceCategoriesController < BaseController
      def index
        categories = current_user.finance_categories.ordered
        render json: { categories: categories.map { |category| Serialize.category(category) } }
      end
    end
  end
end
