import { Controller } from "@hotwired/stimulus"

// Custom finance-category dropdown — replaces the native <select> so the
// panel can render color dots, indented subcategories, and expand/collapse
// each parent. The hidden <input> carries the selected id for form submit.
//
// The transaction-form controller talks to this picker through a Stimulus
// value (`data-category-picker-kind-value`): writing the attribute triggers
// `kindValueChanged()`, which filters the panel. Going through a value
// (not a method call) avoids the controller-bootstrap race where the
// outer form connects before the inner picker is registered.
export default class extends Controller {
  static targets = ["trigger", "panel", "display", "hidden", "group", "children", "chevron"]
  static values = {
    blankLabel: { type: String, default: "" },
    kind: { type: String, default: "" }
  }

  connect() {
    this.documentClick = (e) => { if (!this.element.contains(e.target)) this.close() }
    this.escHandler = (e) => { if (e.key === "Escape" && !this.panelTarget.classList.contains("hidden")) this.close() }
    document.addEventListener("click", this.documentClick)
    document.addEventListener("keydown", this.escHandler)
    this.refreshHighlights()
    this.openGroupContainingSelection()
  }

  disconnect() {
    document.removeEventListener("click", this.documentClick)
    document.removeEventListener("keydown", this.escHandler)
  }

  // Called by Stimulus when the kind value attribute changes (including the
  // initial read on connect). Empty kind = no filter (subscription/account forms).
  kindValueChanged(newKind) {
    if (newKind) {
      this.filterByKind(newKind)
    } else {
      this.unfilter()
    }
  }

  toggle(event) {
    event.preventDefault()
    // No stopPropagation — let the click bubble so sibling pickers close via
    // their own document listener. Our listener guards with element.contains
    // so this picker won't self-close.
    const willOpen = this.panelTarget.classList.contains("hidden")
    this.panelTarget.classList.toggle("hidden", !willOpen)
    if (willOpen) this.openGroupContainingSelection()
  }

  close() {
    this.panelTarget.classList.add("hidden")
  }

  select(event) {
    event.preventDefault()
    event.stopPropagation()
    const btn = event.currentTarget
    this.applySelection(btn.dataset.id || "", btn.dataset.name || "", btn.dataset.color || "")
    this.close()
  }

  toggleGroup(event) {
    event.preventDefault()
    event.stopPropagation()
    const chevron = event.currentTarget
    const group = chevron.closest("[data-category-picker-target='group']")
    const children = group.querySelector("[data-category-picker-target='children']")
    if (!children) return
    const willOpen = children.classList.contains("hidden")
    children.classList.toggle("hidden", !willOpen)
    chevron.setAttribute("aria-expanded", willOpen ? "true" : "false")
    chevron.querySelector("svg")?.classList.toggle("rotate-180", willOpen)
  }

  filterByKind(kind) {
    this.groupTargets.forEach(group => {
      group.hidden = group.dataset.kind !== kind
    })
    const current = this.hiddenTarget.value
    if (!current) return
    const stillVisible = this.element.querySelector(`[data-action*='category-picker#select'][data-id='${current}'][data-kind='${kind}']`)
    if (!stillVisible) this.applySelection("", "", "")
  }

  unfilter() {
    this.groupTargets.forEach(group => { group.hidden = false })
  }

  applySelection(id, name, color) {
    this.hiddenTarget.value = id
    this.updateDisplay(id, name, color)
    this.refreshHighlights()
    this.hiddenTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  updateDisplay(id, name, color) {
    this.displayTarget.innerHTML = ""
    if (id && name) {
      const dot = document.createElement("span")
      dot.className = "w-2.5 h-2.5 rounded-full flex-shrink-0 ring-1 ring-inset ring-[rgba(255,255,255,0.15)]"
      dot.style.background = color
      const text = document.createElement("span")
      text.className = "text-sm truncate"
      text.textContent = name
      text.title = name
      this.displayTarget.append(dot, text)
    } else {
      const blank = document.createElement("span")
      blank.className = "text-sm text-[var(--color-fg-muted)]"
      blank.textContent = this.blankLabelValue
      this.displayTarget.append(blank)
    }
  }

  // Panel is derived state from hiddenTarget.value — recompute highlights
  // so a re-pick doesn't leave the old row marked.
  refreshHighlights() {
    const currentId = this.hiddenTarget.value
    this.element.querySelectorAll("[data-action*='category-picker#select']").forEach(btn => {
      if (!btn.dataset.id) return // skip blank-option row
      const isSelected = btn.dataset.id === currentId && currentId !== ""
      const row = btn.closest("[data-picker-row]") || btn
      row.classList.toggle("bg-[var(--color-bg-hover)]", isSelected)
      const label = btn.querySelector("[data-picker-label]")
      label?.classList.toggle("font-medium", isSelected)
      label?.classList.toggle("text-[var(--color-accent-400)]", isSelected)
    })
  }

  // If a child is currently selected, expand its parent group so the user
  // sees the selection without having to click the chevron first.
  openGroupContainingSelection() {
    const id = this.hiddenTarget.value
    if (!id) return
    const selectedBtn = this.element.querySelector(`[data-action*='category-picker#select'][data-id='${id}']`)
    if (!selectedBtn) return
    const childrenContainer = selectedBtn.closest("[data-category-picker-target='children']")
    if (!childrenContainer) return
    childrenContainer.classList.remove("hidden")
    const group = childrenContainer.closest("[data-category-picker-target='group']")
    const chevron = group?.querySelector("[data-category-picker-target='chevron']")
    chevron?.setAttribute("aria-expanded", "true")
    chevron?.querySelector("svg")?.classList.add("rotate-180")
  }
}
