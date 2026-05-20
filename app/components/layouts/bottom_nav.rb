module Layouts
  class BottomNav < ApplicationComponent
    ITEMS = [
      { key: :dashboard, label: "Home",     icon: "home",     path: "#" },
      { key: :todos,     label: "Todos",    icon: "check",    path: "#" },
      { key: :calendar,  label: "Calendar", icon: "calendar", path: "#" },
      { key: :finance,   label: "Finance",  icon: "wallet",   path: "#" },
      { key: :more,      label: "More",     icon: "menu",     path: "#" }
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
