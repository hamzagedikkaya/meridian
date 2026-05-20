module Ui
  # Minimal inline icon helper. Heroicons setine geçilebilir (Aşama 0.6 sonrası).
  # Şimdilik kabaca her isim için unicode/basit svg dönüyor.
  class Icon < ApplicationComponent
    GLYPHS = {
      "home"     => "⌂",
      "wallet"   => "₿",
      "check"    => "✓",
      "flame"    => "🔥",
      "calendar" => "▦",
      "book"     => "❏",
      "target"   => "◎",
      "search"   => "⌕",
      "plus"     => "+",
      "bell"     => "◔",
      "user"     => "◉",
      "moon"     => "☾",
      "sun"      => "☀",
      "menu"     => "≡"
    }.freeze

    def initialize(name:, size: 20)
      @name = name.to_s
      @size = size
    end

    attr_reader :name, :size

    def glyph
      GLYPHS.fetch(name, "·")
    end

    def call
      content_tag(:span,
        glyph,
        class: "inline-flex items-center justify-center",
        style: "font-size: #{size}px; line-height: 1;",
        aria: { hidden: true }
      )
    end
  end
end
