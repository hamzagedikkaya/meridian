module Ui
  # Renders the "don't break the chain" SVG strip — a row of circular links
  # for each day in the window. Each link's visual state comes from `:status`
  # in the underlying data (:completed, :missed, :today_pending). Three size
  # presets are provided; pass `size:` to pick one.
  #
  #   <%= render Ui::HabitChain.new(links: habit.chain_window, size: :lg) %>
  #
  # `links` is the array produced by Habit#chain_window or
  # PerfectDayChain#to_a; the component does not query anything itself.
  class HabitChain < ApplicationComponent
    SIZE_PRESETS = {
      sm: { radius: 4,  gap: 3, padding: 6 },
      md: { radius: 5,  gap: 3, padding: 8 },
      lg: { radius: 8,  gap: 5, padding: 12 }
    }.freeze

    def initialize(links:, size: :md, aria_label: nil, gradient_id: nil)
      @links = links
      @size = size.to_sym
      @preset = SIZE_PRESETS.fetch(@size)
      @aria_label = aria_label
      @gradient_id = gradient_id || "chain-grad-#{SecureRandom.hex(4)}"
    end

    attr_reader :links, :size, :preset, :aria_label, :gradient_id

    def total_width
      n = links.size
      n * preset[:radius] * 2 + (n - 1) * preset[:gap] + preset[:padding] * 2
    end

    def total_height
      preset[:radius] * 2 + preset[:padding] * 2
    end

    def link_cx(index)
      preset[:padding] + preset[:radius] + index * (preset[:radius] * 2 + preset[:gap])
    end

    def link_cy
      preset[:padding] + preset[:radius]
    end

    def unique_colors
      links.map { |l| l[:color] }.compact.uniq
    end

    def gradient_for(color)
      "#{gradient_id}-#{color.delete('#')}"
    end

    def lighten(hex, amount)
      return hex unless hex.is_a?(String) && hex.start_with?("#")
      num = hex.sub("#", "").to_i(16)
      r = [ ((num >> 16) & 0xff) + (255 * amount).to_i, 255 ].min
      g = [ ((num >> 8) & 0xff) + (255 * amount).to_i, 255 ].min
      b = [ (num & 0xff) + (255 * amount).to_i, 255 ].min
      format("#%02X%02X%02X", r, g, b)
    end

    def status_class(status)
      "chain-link chain-link--#{status}"
    end

    def title_for(link)
      date_str = helpers.l(link[:date], format: "%d %b %Y")
      case link[:status]
      when :today_pending then helpers.t("habits.chain.today_pending")
      when :partial       then helpers.t("habits.chain.partial_on", date: date_str, completed: link[:completed], possible: link[:possible])
      when :no_habits     then helpers.t("habits.chain.no_habits_on", date: date_str)
      else                     helpers.t("habits.chain.#{link[:status]}_on", date: date_str)
      end
    end
  end
end
