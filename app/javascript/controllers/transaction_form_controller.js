import { Controller } from "@hotwired/stimulus"

// Filters the category pickers by kind and toggles the linked-account section.
// Primary picker is filtered to match the chosen kind. Linked side gets the
// inverse kind, since a paired income/expense is the whole point of the link.
//
// Communication with the picker is via the `data-category-picker-kind-value`
// attribute. Setting it triggers the picker's `kindValueChanged` callback,
// which runs even if the picker connects AFTER this form controller. That
// avoids the controller-bootstrap race we hit when we tried direct method calls.
export default class extends Controller {
  static targets = [
    "kindRadio",
    "categoryPicker",
    "linkedToggle",
    "linkedSection",
    "linkedCategoryPicker",
    "linkedKindLabel"
  ]

  connect() {
    this.refresh()
    this.syncLinkedDisabled()
  }

  kindChanged() {
    this.refresh()
  }

  linkedToggled() {
    this.syncLinkedDisabled()
  }

  refresh() {
    const kind = this.currentKind()
    if (!kind) return

    this.setPickerKind(this.categoryPickerTarget, kind)
    if (this.hasLinkedCategoryPickerTarget) {
      const inverse = kind === "income" ? "expense" : "income"
      this.setPickerKind(this.linkedCategoryPickerTarget, inverse)
      if (this.hasLinkedKindLabelTarget) {
        const labelKey = `label${inverse[0].toUpperCase()}${inverse.slice(1)}`
        this.linkedKindLabelTarget.textContent = this.linkedKindLabelTarget.dataset[labelKey] || inverse
      }
    }
  }

  syncLinkedDisabled() {
    if (!this.hasLinkedSectionTarget) return
    const checked = this.hasLinkedToggleTarget && this.linkedToggleTarget.checked
    this.linkedSectionTarget.classList.toggle("hidden", !checked)
    // disabled on the <fieldset> stops its inputs from posting with the form
    this.linkedSectionTarget.disabled = !checked
  }

  currentKind() {
    const checked = this.kindRadioTargets.find(r => r.checked)
    return checked ? checked.value : null
  }

  setPickerKind(pickerEl, kind) {
    if (!pickerEl) return
    pickerEl.setAttribute("data-category-picker-kind-value", kind)
  }
}
