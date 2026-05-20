module Layouts
  class TopBar < ApplicationComponent
    def initialize(title: nil, breadcrumbs: [], user: nil)
      @title = title
      @breadcrumbs = breadcrumbs
      @user = user
    end

    attr_reader :title, :breadcrumbs, :user
  end
end
