import { Controller } from "@hotwired/stimulus"

// Goal form swapper — shows/hides the polymorphic source selector and the
// manual current_value field based on the chosen target_type.
//
//   financial → show "linkedSource", limit options to accounts
//   habit     → show "linkedSource", limit options to habits
//   custom    → hide "linkedSource" entirely, show "currentValueField"
export default class extends Controller {
  static targets = ["linkedSource", "linkedLabel", "linkedHint", "linkedSelect", "accountsGroup", "habitsGroup", "currentValueField"]
  static values  = { currentType: String }

  connect() {
    this.refresh(this.currentTypeValue)
  }

  switch(event) {
    this.refresh(event.target.value)
  }

  refresh(type) {
    switch (type) {
      case "financial":
        this.showLinked()
        this.setLabel("link_account")
        this.toggleGroup(this.accountsGroupTarget, true)
        this.toggleGroup(this.habitsGroupTarget, false)
        this.hideCurrentValue()
        break
      case "habit":
        this.showLinked()
        this.setLabel("link_habit")
        this.toggleGroup(this.accountsGroupTarget, false)
        this.toggleGroup(this.habitsGroupTarget, true)
        this.hideCurrentValue()
        break
      default: // custom
        this.hideLinked()
        this.showCurrentValue()
    }
  }

  showLinked()  { if (this.hasLinkedSourceTarget) this.linkedSourceTarget.classList.remove("hidden") }
  hideLinked()  { if (this.hasLinkedSourceTarget) this.linkedSourceTarget.classList.add("hidden") }
  showCurrentValue() { if (this.hasCurrentValueFieldTarget) this.currentValueFieldTarget.classList.remove("hidden") }
  hideCurrentValue() { if (this.hasCurrentValueFieldTarget) this.currentValueFieldTarget.classList.add("hidden") }

  toggleGroup(group, visible) {
    if (!group) return
    // <optgroup> can't be hidden via CSS in all browsers, so flag the disabled
    // attribute on the contained <option>s; the group label stays but options
    // become unselectable, and we visually emphasize the right group via the
    // disabled-options being grayed out.
    group.disabled = !visible
    if (!visible) {
      // Clear any selected option in this group so the form doesn't submit it
      Array.from(group.children).forEach(opt => { if (opt.selected) opt.selected = false })
    }
  }

  setLabel(key) {
    if (!this.hasLinkedLabelTarget) return
    const labels = {
      link_account: this.linkedLabelTarget.dataset.linkAccount || this.linkedLabelTarget.textContent,
      link_habit:   this.linkedLabelTarget.dataset.linkHabit   || this.linkedLabelTarget.textContent
    }
    // Best-effort: just leave the existing label, browsers handle disabled optgroups OK
  }
}
