module Layouts
  class Sidebar < ApplicationComponent
    NAV_ITEMS = [
      { key: :dashboard, label: "Dashboard", icon: "home",     path: "/" },
      { key: :finance,   label: "Finance",   icon: "wallet",   path: "/finance" },
      { key: :todos,     label: "Todos",     icon: "check",    path: "/todos" },
      { key: :habits,    label: "Habits",    icon: "flame",    path: "/habits" },
      { key: :calendar,  label: "Calendar",  icon: "calendar", path: "/calendar" },
      { key: :journal,   label: "Journal",   icon: "book",     path: "/journal" },
      { key: :goals,     label: "Goals",     icon: "target",   path: "#" }
    ].freeze

    def initialize(active: nil, collapsed: false)
      @active = active
      @collapsed = collapsed
    end

    attr_reader :active, :collapsed

    def active?(key)
      active == key
    end
  end
end
