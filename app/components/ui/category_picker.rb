module Ui
  # Finance-category / account dropdown with color dots and (optional)
  # collapsible subcategories. Duck-typed: each item needs id/name/color;
  # parent_id and kind are optional (account records, with no parent or kind,
  # just render as a flat list).
  #
  #   <%= render Ui::CategoryPicker.new(
  #         name: "transaction[finance_category_id]",
  #         categories: all_categories,
  #         selected_id: transaction.finance_category_id,
  #         blank_label: "Kategori seç…",
  #         extra_data: { "transaction-form-target" => "categoryPicker" }) %>
  #
  # The transaction-form controller drives kind filtering through the Stimulus
  # value `data-category-picker-kind-value` (income/expense) — see the JS
  # controller for the contract.
  class CategoryPicker < ApplicationComponent
    def initialize(name:, categories:, selected_id: nil, blank_label: nil, extra_data: {}, input_class: nil)
      @name = name
      @categories = categories
      @selected_id = selected_id
      @blank_label = blank_label
      @extra_data = extra_data
      @input_class = input_class
    end

    attr_reader :name, :selected_id, :blank_label, :extra_data, :input_class

    def roots
      @roots ||= @categories.select { |c| !has_parent?(c) }.sort_by { |c| [ kind_of(c).to_s, c.name.to_s.downcase ] }
    end

    def children_for(root)
      @children_by_parent ||= @categories.select { |c| has_parent?(c) }.group_by(&:parent_id)
      (@children_by_parent[root.id] || []).sort_by { |c| c.name.to_s.downcase }
    end

    def selected
      return nil if selected_id.blank?
      @selected ||= @categories.find { |c| c.id == selected_id.to_i }
    end

    def trigger_classes
      input_class.presence ||
        "w-full px-3.5 py-2.5 bg-[var(--color-bg-base)] border border-[var(--color-border-default)] rounded-[var(--radius-sm)] text-[var(--color-fg-primary)] focus:outline-none focus:border-[var(--color-accent-500)] transition-colors"
    end

    def root_data
      { controller: "category-picker", "category-picker-blank-label-value": blank_label.to_s }.merge(extra_data)
    end

    # Only surface the search box when the list is long enough to be worth
    # filtering — a 3-account dropdown doesn't need one.
    def searchable?
      @categories.size > 6
    end

    private

    def has_parent?(item)
      item.respond_to?(:parent_id) && item.parent_id.present?
    end

    def kind_of(item)
      item.respond_to?(:kind) ? item.kind : nil
    end
  end
end
