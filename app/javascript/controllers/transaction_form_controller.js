import { Controller } from "@hotwired/stimulus"

// Filters the category selects by kind and toggles the linked-account section.
// Primary category is filtered to match the chosen kind. Linked side gets the
// inverse kind, since a paired income/expense is the whole point of the link.
export default class extends Controller {
  static targets = [
    "kindRadio",
    "categorySelect",
    "linkedToggle",
    "linkedSection",
    "linkedCategorySelect",
    "linkedKindLabel"
  ]

  connect() {
    this.refresh()
  }

  kindChanged() {
    this.refresh()
  }

  linkedToggled() {
    if (!this.hasLinkedSectionTarget) return
    this.linkedSectionTarget.classList.toggle("hidden", !this.linkedToggleTarget.checked)
  }

  refresh() {
    const kind = this.currentKind()
    if (!kind) return

    this.filterOptions(this.categorySelectTarget, kind)
    if (this.hasLinkedCategorySelectTarget) {
      const inverse = kind === "income" ? "expense" : "income"
      this.filterOptions(this.linkedCategorySelectTarget, inverse)
      if (this.hasLinkedKindLabelTarget) {
        this.linkedKindLabelTarget.textContent =
          this.linkedKindLabelTarget.dataset[inverse] ||
          this.linkedKindLabelTarget.dataset[`label-${inverse}`] ||
          inverse
      }
    }
  }

  currentKind() {
    const checked = this.kindRadioTargets.find(r => r.checked)
    return checked ? checked.value : null
  }

  filterOptions(select, kind) {
    if (!select) return
    let resetSelection = false
    Array.from(select.options).forEach(opt => {
      if (!opt.value) return
      const matches = opt.dataset.kind === kind
      opt.hidden = !matches
      opt.disabled = !matches
      if (!matches && opt.selected) {
        opt.selected = false
        resetSelection = true
      }
    })
    if (resetSelection) select.value = ""
  }
}
