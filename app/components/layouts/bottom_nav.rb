module Layouts
  class BottomNav < ApplicationComponent
    ITEMS = [
      { key: :dashboard, label_key: "nav.dashboard", icon: "home",       path: "/" },
      { key: :todos,     label_key: "nav.todos",     icon: "list-check", path: "/todos" },
      { key: :calendar,  label_key: "nav.calendar",  icon: "calendar",   path: "/calendar" },
      { key: :finance,   label_key: "nav.finance",   icon: "wallet",     path: "/finance" },
      { key: :more,      label_key: "nav.more",      icon: "menu",       path: "/settings" }
    ].freeze

    def initialize(active: nil)
      @active = active
    end

    attr_reader :active

    def active?(key)
      active == key
    end
  end
end
