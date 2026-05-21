module Ui
  # Inline SVG icon component using Lucide icon paths (https://lucide.dev, ISC license).
  # Renders 24x24 viewBox SVGs with stroke="currentColor" so they pick up the parent
  # text color and theme. Use it as: <%= render Ui::Icon.new(name: "wallet", size: 20) %>
  class Icon < ApplicationComponent
    # Each value is just the inner markup of the SVG (paths/lines/circles/etc).
    # Sourced from Lucide v0.x — all use 24x24 viewBox with stroke="currentColor".
    PATHS = {
      "home"          => '<path d="M15 21v-8a1 1 0 0 0-1-1h-4a1 1 0 0 0-1 1v8"/><path d="M3 10a2 2 0 0 1 .709-1.528l7-5.999a2 2 0 0 1 2.582 0l7 5.999A2 2 0 0 1 21 10v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',

      "wallet"        => '<path d="M19 7V4a1 1 0 0 0-1-1H5a2 2 0 0 0 0 4h15a1 1 0 0 1 1 1v4h-3a2 2 0 0 0 0 4h3a1 1 0 0 0 1-1v-2a1 1 0 0 0-1-1"/><path d="M3 5v14a2 2 0 0 0 2 2h15a1 1 0 0 0 1-1v-4"/>',

      "check"         => '<path d="M20 6 9 17l-5-5"/>',

      "list-check"    => '<path d="M11 5h10"/><path d="M11 19h10"/><path d="M11 12h10"/><path d="m3 5 2 2 4-4"/><path d="m3 17 2 2 4-4"/><path d="m3 10 2 2 4-4"/>',

      "circle-check"  => '<circle cx="12" cy="12" r="10"/><path d="m9 12 2 2 4-4"/>',

      "flame"         => '<path d="M8.5 14.5A2.5 2.5 0 0 0 11 12c0-1.38-.5-2-1-3-1.072-2.143-.224-4.054 2-6 .5 2.5 2 4.9 4 6.5 2 1.6 3 3.5 3 5.5a7 7 0 1 1-14 0c0-1.153.433-2.294 1-3a2.5 2.5 0 0 0 2.5 2.5z"/>',

      "calendar"      => '<path d="M8 2v4"/><path d="M16 2v4"/><rect width="18" height="18" x="3" y="4" rx="2"/><path d="M3 10h18"/>',

      "book"          => '<path d="M12 7v14"/><path d="M3 18a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h5a4 4 0 0 1 4 4 4 4 0 0 1 4-4h5a1 1 0 0 1 1 1v13a1 1 0 0 1-1 1h-6a3 3 0 0 0-3 3 3 3 0 0 0-3-3z"/>',

      "target"        => '<circle cx="12" cy="12" r="10"/><circle cx="12" cy="12" r="6"/><circle cx="12" cy="12" r="2"/>',

      "search"        => '<path d="m21 21-4.34-4.34"/><circle cx="11" cy="11" r="8"/>',

      "plus"          => '<path d="M5 12h14"/><path d="M12 5v14"/>',

      "bell"          => '<path d="M10.268 21a2 2 0 0 0 3.464 0"/><path d="M3.262 15.326A1 1 0 0 0 4 17h16a1 1 0 0 0 .74-1.673C19.41 13.956 18 12.499 18 8A6 6 0 0 0 6 8c0 4.499-1.411 5.956-2.738 7.326"/>',

      "user"          => '<path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/>',

      "moon"          => '<path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/>',

      "sun"           => '<circle cx="12" cy="12" r="4"/><path d="M12 2v2"/><path d="M12 20v2"/><path d="m4.93 4.93 1.41 1.41"/><path d="m17.66 17.66 1.41 1.41"/><path d="M2 12h2"/><path d="M20 12h2"/><path d="m6.34 17.66-1.41 1.41"/><path d="m19.07 4.93-1.41 1.41"/>',

      "menu"          => '<path d="M4 12h16"/><path d="M4 18h16"/><path d="M4 6h16"/>',

      "chevron-down"  => '<path d="m6 9 6 6 6-6"/>',
      "chevron-left"  => '<path d="m15 18-6-6 6-6"/>',
      "chevron-right" => '<path d="m9 18 6-6-6-6"/>',
      "chevron-up"    => '<path d="m18 15-6-6-6 6"/>',

      "x"             => '<path d="M18 6 6 18"/><path d="m6 6 12 12"/>',

      "panel-left"    => '<rect width="18" height="18" x="3" y="3" rx="2"/><path d="M9 3v18"/>',

      "settings"      => '<path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z"/><circle cx="12" cy="12" r="3"/>',

      "log-out"       => '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" x2="9" y1="12" y2="12"/>',

      "trending-up"   => '<polyline points="22 7 13.5 15.5 8.5 10.5 2 17"/><polyline points="16 7 22 7 22 13"/>',

      "sparkles"      => '<path d="M9.937 15.5A2 2 0 0 0 8.5 14.063l-6.135-1.582a.5.5 0 0 1 0-.962L8.5 9.936A2 2 0 0 0 9.937 8.5l1.582-6.135a.5.5 0 0 1 .963 0L14.063 8.5A2 2 0 0 0 15.5 9.937l6.135 1.581a.5.5 0 0 1 0 .964L15.5 14.063a2 2 0 0 0-1.437 1.437l-1.582 6.135a.5.5 0 0 1-.963 0z"/>',

      "database"      => '<ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M3 5V19A9 3 0 0 0 21 19V5"/><path d="M3 12A9 3 0 0 0 21 12"/>',

      "lock"          => '<rect width="18" height="11" x="3" y="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>',

      "image"         => '<rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/>'
    }.freeze

    def initialize(name:, size: 20, classes: nil)
      @name = name.to_s
      @size = size
      @classes = classes
    end

    attr_reader :name, :size, :classes

    def call
      path = PATHS.fetch(name) do
        # Fallback to a small dot if icon name is unknown
        '<circle cx="12" cy="12" r="2"/>'
      end

      tag.svg(
        path.html_safe,
        xmlns: "http://www.w3.org/2000/svg",
        width: size, height: size,
        viewBox: "0 0 24 24",
        fill: "none",
        stroke: "currentColor",
        "stroke-width": 1.75,
        "stroke-linecap": "round",
        "stroke-linejoin": "round",
        class: [ "inline-block flex-shrink-0", classes ].compact.join(" "),
        "aria-hidden": "true"
      )
    end
  end
end
