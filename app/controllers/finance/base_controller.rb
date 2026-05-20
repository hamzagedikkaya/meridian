module Finance
  class BaseController < ApplicationController
    private

    def user_accounts
      current_user.accounts.active.order(:name)
    end

    def user_categories(kind = nil)
      scope = current_user.finance_categories.ordered
      kind ? scope.where(kind: kind) : scope
    end
  end
end
