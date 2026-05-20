module Layouts
  class Sidebar < ApplicationComponent
    NAV_ITEMS = [
      { key: :dashboard, label_key: "nav.dashboard", icon: "home",     path: "/" },
      { key: :finance,   label_key: "nav.finance",   icon: "wallet",   path: "/finance" },
      { key: :todos,     label_key: "nav.todos",     icon: "check",    path: "/todos" },
      { key: :habits,    label_key: "nav.habits",    icon: "flame",    path: "/habits" },
      { key: :calendar,  label_key: "nav.calendar",  icon: "calendar", path: "/calendar" },
      { key: :journal,   label_key: "nav.journal",   icon: "book",     path: "/journal" },
      { key: :goals,     label_key: "nav.goals",     icon: "target",   path: "/goals" }
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
